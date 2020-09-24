# Go cross compiler (xgo): Go 1.14.7
# Copyright (c) 2019 Péter Szilágyi. All rights reserved.
#
# Released under the MIT license.

FROM nicklas/xgo-base

MAINTAINER Péter Szilágyi <peterke@gmail.com>

ENV ANDROID_CHAIN_x86_64   x86_64-4.9


# Configure the root Go distribution and bootstrap based on it
ENV GO_VERSION 11403

ADD build_all_deps.sh /build_all_deps.sh
ENV BUILD_ALL_DEPS /build_all_deps.sh
RUN chmod +x $BUILD_ALL_DEPS

ADD build_deps.sh /build_deps.sh
ENV BUILD_DEPS /build_deps.sh
RUN chmod +x $BUILD_DEPS


ENTRYPOINT ["/build_all_deps.sh"]