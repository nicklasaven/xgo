#!/bin/bash
#
# Contains the main cross compiler, that individually sets up each target build
# platform, compiles all the C dependencies, then build the requested executable
# itself.
#
# Usage: build.sh <import path>
#
# Needed environment variables:
#   REPO_REMOTE    - Optional VCS remote if not the primary repository is needed
#   REPO_BRANCH    - Optional VCS branch to use, if not the master branch
#   DEPS           - Optional list of C dependency packages to build
#   ARGS           - Optional arguments to pass to C dependency configure scripts
#   PACK           - Optional sub-package, if not the import path is being built
#   OUT            - Optional output prefix to override the package name
#   FLAG_V         - Optional verbosity flag to set on the Go builder
#   FLAG_X         - Optional flag to print the build progress commands
#   FLAG_RACE      - Optional race flag to set on the Go builder
#   FLAG_TAGS      - Optional tag flag to set on the Go builder
#   FLAG_LDFLAGS   - Optional ldflags flag to set on the Go builder
#   FLAG_BUILDMODE - Optional buildmode flag to set on the Go builder
#   TARGETS        - Comma separated list of build targets to compile for
#   GO_VERSION     - Bootstrapped version of Go to disable uncupported targets
#   EXT_GOPATH     - GOPATH elements mounted from the host filesystem

# Define a function that figures out the binary extension
function extension {
  if [ "$FLAG_BUILDMODE" == "archive" ] || [ "$FLAG_BUILDMODE" == "c-archive" ]; then
    if [ "$1" == "windows" ]; then
      echo ".lib"
    else
      echo ".a"
    fi
  elif [ "$FLAG_BUILDMODE" == "shared" ] || [ "$FLAG_BUILDMODE" == "c-shared" ]; then
    if [ "$1" == "windows" ]; then
      echo ".dll"
    elif [ "$1" == "darwin" ] || [ "$1" == "ios" ]; then
      echo ".dylib"
    else
      echo ".so"
    fi
  else
    if [ "$1" == "windows" ]; then
      echo ".exe"
    fi
  fi
}

# Either set a local build environemnt, or pull any remote imports


OUT_DIR="/build/deps"



# Download all the C dependencies
mkdir /deps
DEPS=($DEPS) && for dep in "${DEPS[@]}"; do
  if [ "${dep##*.}" == "tar" ]; then cat "/deps-cache/`basename $dep`" | tar -C /deps -x --atime-preserve; fi
  if [ "${dep##*.}" == "gz" ];  then cat "/deps-cache/`basename $dep`" | tar -C /deps -xz --atime-preserve; fi
  if [ "${dep##*.}" == "bz2" ]; then cat "/deps-cache/`basename $dep`" | tar -C /deps -xj --atime-preserve; fi
done

DEPS_ARGS=($ARGS)

# Save the contents of the pre-build /usr/local folder for post cleanup
USR_LOCAL_CONTENTS=`ls /usr/local`

# Configure some global build parameters
NAME=`basename $1/$PACK`
if [ "$OUT" != "" ]; then
  NAME=$OUT
fi

if [ "$FLAG_V" == "true" ];    then V=-v; fi
if [ "$FLAG_X" == "true" ];    then X=-x; fi
if [ "$FLAG_RACE" == "true" ]; then R=-race; fi
if [ "$FLAG_TAGS" != "" ];     then T=(--tags "$FLAG_TAGS"); fi
if [ "$FLAG_LDFLAGS" != "" ];  then LD="$FLAG_LDFLAGS"; fi

if [ "$FLAG_BUILDMODE" != "" ] && [ "$FLAG_BUILDMODE" != "default" ]; then BM="--buildmode=$FLAG_BUILDMODE"; fi

# If no build targets were specified, inject a catch all wildcard
if [ "$TARGETS" == "" ]; then
  TARGETS="./."
fi

# Build for each requested platform individually
for TARGET in $TARGETS; do
  echo "targets: $TARGETS"
  # Split the target into platform and architecture
  XGOOS=`echo $TARGET | cut -d '/' -f 1`
  XGOARCH=`echo $TARGET | cut -d '/' -f 2`

  # Check and build for Android targets
  if ([ $XGOOS == "." ] || [[ $XGOOS == android* ]]); then
    # Split the platform version and configure the linker options
    PLATFORM=`echo $XGOOS | cut -d '-' -f 2`
    if [ "$PLATFORM" == "" ] || [ "$PLATFORM" == "." ] || [ "$PLATFORM" == "android" ]; then
      PLATFORM=16 # Jelly Bean 4.0.0
    fi
    if [ "$PLATFORM" -ge 16 ]; then
      CGO_CCPIE="-fPIE"
      CGO_LDPIE="-fPIE"
      EXT_LDPIE="-extldflags=-pie"
    else
      unset CGO_CCPIE CGO_LDPIE EXT_LDPIE
    fi
    mkdir -p /build-android-aar

    # Iterate over the requested architectures, bootstrap and build
    if [ $XGOARCH == "." ] || [ $XGOARCH == "arm" ] || [ $XGOARCH == "aar" ]; then
        # Include a linker workaround for pre Go 1.6 releases
        if [ "$GO_VERSION" -lt 160 ]; then
          EXT_LDAMD="-extldflags=-Wl,--allow-multiple-definition"
        fi

        echo "Assembling toolchain for android-$PLATFORM/arm..."
        $ANDROID_NDK_ROOT/build/tools/make-standalone-toolchain.sh --ndk-dir=$ANDROID_NDK_ROOT --install-dir=/usr/$ANDROID_CHAIN_ARM --toolchain=$ANDROID_CHAIN_ARM --arch=arm > /dev/null 2>&1

        echo "Compiling for android-$PLATFORM/arm..."
        CC=arm-linux-androideabi-gcc CXX=arm-linux-androideabi-g++ HOST=arm-linux-androideabi PREFIX=$OUT_DIR/usr/$ANDROID_CHAIN_ARM/arm-linux-androideabi $BUILD_DEPS /deps ${DEPS_ARGS[@]}
        export PKG_CONFIG_PATH=/usr/$ANDROID_CHAIN_ARM/arm-linux-androideabi/lib/pkgconfig

    fi

      if [ "$PLATFORM" -ge 9 ] && ([ $XGOARCH == "." ] || [ $XGOARCH == "386" ] || [ $XGOARCH == "aar" ]); then
        echo "Assembling toolchain for android-$PLATFORM/386..."
        $ANDROID_NDK_ROOT/build/tools/make-standalone-toolchain.sh --ndk-dir=$ANDROID_NDK_ROOT --install-dir=/usr/$ANDROID_CHAIN_386 --toolchain=$ANDROID_CHAIN_386 --arch=x86 > /dev/null 2>&1


        echo "Compiling for android-$PLATFORM/386..."
        CC=i686-linux-android-gcc CXX=i686-linux-android-g++ HOST=i686-linux-android PREFIX=$OUT_DIR/usr/$ANDROID_CHAIN_386/i686-linux-android $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  
      fi

      if [ "$PLATFORM" -ge 21 ] && ([ $XGOARCH == "." ] || [ $XGOARCH == "arm64" ] || [ $XGOARCH == "aar" ]); then
        echo "Assembling toolchain for android-$PLATFORM/arm64..."
        $ANDROID_NDK_ROOT/build/tools/make-standalone-toolchain.sh --ndk-dir=$ANDROID_NDK_ROOT --install-dir=/usr/$ANDROID_CHAIN_ARM64 --toolchain=$ANDROID_CHAIN_ARM64 --arch=arm64 > /dev/null 2>&1


        echo "Compiling for android-$PLATFORM/arm64..."
        CC=aarch64-linux-android-gcc CXX=aarch64-linux-android-g++ HOST=aarch64-linux-android PREFIX=$OUT_DIR/usr/$ANDROID_CHAIN_ARM64/aarch64-linux-android $BUILD_DEPS /deps ${DEPS_ARGS[@]}
    
      fi
    # Clean up the android builds, toolchains and runtimes
    rm -rf /build-android-aar
    rm -rf /usr/local/go/pkg/android_*
    rm -rf /usr/$ANDROID_CHAIN_ARM /usr/$ANDROID_CHAIN_ARM64 /usr/$ANDROID_CHAIN_386
  fi
  
  
  
  # Check and build for Linux targets
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "amd64" ]); then
    echo "Compiling for linux/amd64..."
    HOST=x86_64-linux PREFIX=$OUT_DIR/usr/local $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "386" ]); then
    echo "Compiling for linux/386..."
    HOST=i686-linux PREFIX=$OUT_DIR/usr/local $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "arm" ] || [ $XGOARCH == "arm-5" ]); then
    echo "Compiling for linux/arm-5..."
    CC=arm-linux-gnueabi-gcc-8 CXX=arm-linux-gnueabi-g++-5 HOST=arm-linux-gnueabi PREFIX=$OUT_DIR/usr/arm-linux-gnueabi CFLAGS="-march=armv5" CXXFLAGS="-march=armv5" $BUILD_DEPS /deps ${DEPS_ARGS[@]}

  fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "arm-6" ]); then

      CC=arm-linux-gnueabi-gcc-8 CXX=arm-linux-gnueabi-g++-5 HOST=arm-linux-gnueabi PREFIX=$OUT_DIR/usr/arm-linux-gnueabi CFLAGS="-march=armv6" CXXFLAGS="-march=armv6" $BUILD_DEPS /deps ${DEPS_ARGS[@]}
   
  fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "arm-7" ]); then

      echo "Compiling for linux/arm-7..."
      CC=arm-linux-gnueabihf-gcc-8 CXX=arm-linux-gnueabihf-g++-5 HOST=arm-linux-gnueabihf PREFIX=$OUT_DIR/usr/arm-linux-gnueabihf CFLAGS="-march=armv7-a -fPIC" CXXFLAGS="-march=armv7-a -fPIC" $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  
 fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "arm64" ]); then
      echo "Compiling for linux/arm64..."
      CC=aarch64-linux-gnu-gcc-8 CXX=aarch64-linux-gnu-g++-5 HOST=aarch64-linux-gnu PREFIX=$OUT_DIR/usr/aarch64-linux-gnu $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "mips64" ]); then
      echo "Compiling for linux/mips64..."
      CC=mips64-linux-gnuabi64-gcc-8 CXX=mips64-linux-gnuabi64-g++-5 HOST=mips64-linux-gnuabi64 PREFIX=$OUT_DIR/usr/mips64-linux-gnuabi64 $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "mips64le" ]); then
      echo "Compiling for linux/mips64le..."
      CC=mips64el-linux-gnuabi64-gcc-8 CXX=mips64el-linux-gnuabi64-g++-5 HOST=mips64el-linux-gnuabi64 PREFIX=$OUT_DIR/usr/mips64el-linux-gnuabi64 $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "mips" ]); then
      echo "Compiling for linux/mips..."
      CC=mips-linux-gnu-gcc-8 CXX=mips-linux-gnu-g++-5 HOST=mips-linux-gnu PREFIX=$OUT_DIR/usr/mips-linux-gnu $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  fi
  if ([ $XGOOS == "." ] || [ $XGOOS == "linux" ]) && ([ $XGOARCH == "." ] || [ $XGOARCH == "mipsle" ]); then
      echo "Compiling for linux/mipsle..."
      CC=mipsel-linux-gnu-gcc-8 CXX=mipsel-linux-gnu-g++-5 HOST=mipsel-linux-gnu PREFIX=$OUT_DIR/usr/mipsel-linux-gnu $BUILD_DEPS /deps ${DEPS_ARGS[@]}
  fi
  # Check and build for Windows targets
  if [ $XGOOS == "." ] || [[ $XGOOS == windows* ]]; then
    # Split the platform version and configure the Windows NT version
    PLATFORM=`echo $XGOOS | cut -d '-' -f 2`
    if [ "$PLATFORM" == "" ] || [ "$PLATFORM" == "." ] || [ "$PLATFORM" == "windows" ]; then
      PLATFORM=4.0 # Windows NT
    fi

    MAJOR=`echo $PLATFORM | cut -d '.' -f 1`
    if [ "${PLATFORM/.}" != "$PLATFORM" ] ; then
      MINOR=`echo $PLATFORM | cut -d '.' -f 2`
    fi
    CGO_NTDEF="-D_WIN32_WINNT=0x`printf "%02d" $MAJOR``printf "%02d" $MINOR`"

    # Build the requested windows binaries
    if [ $XGOARCH == "." ] || [ $XGOARCH == "amd64" ]; then
      echo "Compiling for windows-$PLATFORM/amd64..."
      CC=x86_64-w64-mingw32-gcc-posix CXX=x86_64-w64-mingw32-g++-posix HOST=x86_64-w64-mingw32 PREFIX=$OUT_DIR/usr/x86_64-w64-mingw32 $BUILD_DEPS /deps ${DEPS_ARGS[@]}
    fi
    if [ $XGOARCH == "." ] || [ $XGOARCH == "386" ]; then
      echo "Compiling for windows-$PLATFORM/386..."
      CC=i686-w64-mingw32-gcc-posix CXX=i686-w64-mingw32-g++-posix HOST=i686-w64-mingw32 PREFIX=$OUT_DIR/usr/i686-w64-mingw32 $BUILD_DEPS /deps ${DEPS_ARGS[@]}
     fi
  fi
  # Check and build for OSX targets
  if [ $XGOOS == "." ] || [[ $XGOOS == darwin* ]]; then
    # Split the platform version and configure the deployment target
    PLATFORM=`echo $XGOOS | cut -d '-' -f 2`
    if [ "$PLATFORM" == "" ] || [ "$PLATFORM" == "." ] || [ "$PLATFORM" == "darwin" ]; then
      PLATFORM=10.6 # OS X Snow Leopard
    fi
    export MACOSX_DEPLOYMENT_TARGET=$PLATFORM

    # Strip symbol table below Go 1.6 to prevent DWARF issues
    LDSTRIP=""
    if [ "$GO_VERSION" -lt 160 ]; then
      LDSTRIP="-s"
    fi
    # Build the requested darwin binaries
    if [ $XGOARCH == "." ] || [ $XGOARCH == "amd64" ]; then
      echo "Compiling for darwin-$PLATFORM/amd64..."
      CC=o64-clang CXX=o64-clang++ HOST=x86_64-apple-darwin15 PREFIX=$OUT_DIR/usr/local $BUILD_DEPS /deps ${DEPS_ARGS[@]}
    fi
    if [ $XGOARCH == "." ] || [ $XGOARCH == "386" ]; then
      echo "Compiling for darwin-$PLATFORM/386..."
      CC=o32-clang CXX=o32-clang++ HOST=i386-apple-darwin15 PREFIX=$OUT_DIR/usr/local $BUILD_DEPS /deps ${DEPS_ARGS[@]}
     fi
    # Remove any automatically injected deployment target vars
    unset MACOSX_DEPLOYMENT_TARGET
  fi
  # Check and build for iOS targets
  if [ $XGOOS == "." ] || [[ $XGOOS == ios* ]]; then
    echo "XGOOS = $XGOOS"
    # Split the platform version and configure the deployment target
    PLATFORM=`echo $XGOOS | cut -d '-' -f 2`
    if [ "$PLATFORM" == "" ] || [ "$PLATFORM" == "." ] || [ "$PLATFORM" == "ios" ]; then
      PLATFORM=5.0 # first iPad and upwards
    fi
    export IPHONEOS_DEPLOYMENT_TARGET=$PLATFORM

    # Build the requested iOS binaries
    if [ "$GO_VERSION" -lt 150 ]; then
      echo "Go version too low, skipping ios..."
    else
      # Add the 'ios' tag to all builds, otherwise the std libs will fail
      if [ "$FLAG_TAGS" != "" ]; then
        IOSTAGS=(--tags "ios $FLAG_TAGS")
      else
        IOSTAGS=(--tags ios)
      fi
      mkdir -p /build-ios-fw

      # Strip symbol table below Go 1.6 to prevent DWARF issues
      LDSTRIP=""
      if [ "$GO_VERSION" -lt 160 ]; then
        LDSTRIP="-s"
      fi
      # Cross compile to all available iOS and simulator platforms
      if [ -d "$IOS_NDK_ARM_7" ] && ([ $XGOARCH == "." ] || [ $XGOARCH == "arm-7" ] || [ $XGOARCH == "framework" ]); then
        echo "Bootstrapping ios-$PLATFORM/arm-7..."
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/ios-ndk-arm-7/lib
        export PATH=$IOS_NDK_ARM_7/bin:$PATH
        GOOS=darwin GOARCH=arm GOARM=7 CGO_ENABLED=1 CC=arm-apple-darwin11-clang go install --tags ios std

        echo "Compiling for ios-$PLATFORM/arm-7..."
        CC=arm-apple-darwin11-clang CXX=arm-apple-darwin11-clang++ HOST=arm-apple-darwin11 PREFIX=$OUT_DIR/usr/local $BUILD_DEPS /deps ${DEPS_ARGS[@]}
 
        echo "Cleaning up Go runtime for ios-$PLATFORM/arm-7..."
        rm -rf /usr/local/go/pkg/darwin_arm
      fi
      if [ -d "$IOS_NDK_ARM64" ] && ([ $XGOARCH == "." ] || [ $XGOARCH == "arm64" ] || [ $XGOARCH == "framework" ]); then
        echo "Bootstrapping ios-$PLATFORM/arm64..."
        export PATH=$IOS_NDK_ARM64/bin:$PATH
        GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 CC=arm-apple-darwin11-clang go install --tags ios std

        echo "Compiling for ios-$PLATFORM/arm64..."
        CC=arm-apple-darwin11-clang CXX=arm-apple-darwin11-clang++ HOST=arm-apple-darwin11 PREFIX=$OUT_DIR/usr/local $BUILD_DEPS /deps ${DEPS_ARGS[@]}
	echo "Cleaning up Go runtime for ios-$PLATFORM/arm64..."
        rm -rf /usr/local/go/pkg/darwin_arm64
      fi
      echo "XGOARCH = $XGOARCH"
      if [ -d "$IOS_SIM_NDK_AMD64" ] && ([ $XGOARCH == "." ] || [ $XGOARCH == "amd64" ] || [ $XGOARCH == "framework" ]); then
        echo "Bootstrapping ios-$PLATFORM/amd64..."
        export PATH=$IOS_SIM_NDK_AMD64/bin:$PATH
        mv /usr/local/go/pkg/darwin_amd64 /usr/local/go/pkg/darwin_amd64_bak
        GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 CC=arm-apple-darwin11-clang go install --tags ios std

        echo "Compiling for ios-$PLATFORM/amd64..."
        CC=arm-apple-darwin11-clang CXX=arm-apple-darwin11-clang++ HOST=arm-apple-darwin11 PREFIX=$OUT_DIR/usr/local $BUILD_DEPS /deps ${DEPS_ARGS[@]}
        echo "Cleaning up Go runtime for ios-$PLATFORM/amd64..."
        rm -rf /usr/local/go/pkg/darwin_amd64
        mv /usr/local/go/pkg/darwin_amd64_bak /usr/local/go/pkg/darwin_amd64
      fi
      # Assemble the iOS framework from the built binaries
      if [ $XGOARCH == "." ] || [ $XGOARCH == "framework" ]; then
        title=${NAME^}
        framework=/build/$NAME-ios-$PLATFORM-framework/$title.framework

        rm -rf $framework
        mkdir -p $framework/Versions/A
        (cd $framework/Versions && ln -nsf A Current)

        arches=()
        for lib in `ls /build-ios-fw | grep -e '\.a$'`; do
          arches+=("-arch" "`echo ${lib##*-} | cut -d '.' -f 1`" "/build-ios-fw/$lib")
        done
        arm-apple-darwin11-lipo -create "${arches[@]}" -o $framework/Versions/A/$title
        arm-apple-darwin11-ranlib $framework/Versions/A/$title
        (cd $framework && ln -nsf Versions/A/$title $title)

        mkdir -p $framework/Versions/A/Headers
        for header in `ls /build-ios-fw | grep -e '\.h$'`; do
          cp -f /build-ios-fw/$header $framework/Versions/A/Headers/$title.h
        done
        (cd $framework && ln -nsf Versions/A/Headers Headers)

        mkdir -p $framework/Versions/A/Resources
        echo -e "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n</dict>\n</plist>" > $framework/Versions/A/Resources/Info.plist
        (cd $framework && ln -nsf Versions/A/Resources Resources)

        mkdir -p $framework/Versions/A/Modules
        echo -e "framework module \"$title\" {\n  header \"$title.h\"\n  export *\n}" > $framework/Versions/A/Modules/module.modulemap
        (cd $framework && ln -nsf Versions/A/Modules Modules)

        chmod 777 -R /build/$NAME-ios-$PLATFORM-framework
      fi
      rm -rf /build-ios-fw
    fi
    # Remove any automatically injected deployment target vars
    unset IPHONEOS_DEPLOYMENT_TARGET
  fi
done

# Clean up any leftovers for subsequent build invocations
echo "Cleaning up build environment..."
rm -rf /deps

