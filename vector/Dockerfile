# syntax=docker/dockerfile:1


## stage: builder
FROM zncdatadev/image/kubedoop-base AS builder

ARG PRODUCT_VERSION
ARG INOTIFY_TOOLS_VERSION

RUN <<EOF
    microdnf update
    microdnf install \
        autoconf \
        automake \
        gcc-c++ \
        gzip \
        libtool \
        tar \
        xz
EOF

WORKDIR /build

RUN <<EOF
    set -ex
    ARCH=$(uname -m)
    ARCH="${ARCH/amd64/x86_64}"
    ARCH="${ARCH/arm64/aarch64}"

    mkdir -p vector
    pushd vector

    # https://packages.timber.io/vector/0.42.0/vector-0.42.0-1.aarch64.rpm
    curl -sSfL --proto '=https' --tlsv1.2 \
        -o vector-${PRODUCT_VERSION}-1.${ARCH}.rpm \
        https://packages.timber.io/vector/${PRODUCT_VERSION}/vector-${PRODUCT_VERSION}-1.${ARCH}.rpm

EOF

# smoke test
RUN test -f /build/vector/vector-${PRODUCT_VERSION}-1.*.rpm

# bunld inotify-tools
RUN <<EOF
    set -ex
    mkdir -p inotify-tools
    pushd inotify-tools
    curl -sSfL \
        https://github.com/inotify-tools/inotify-tools/archive/refs/tags/${INOTIFY_TOOLS_VERSION}.tar.gz | \
        tar xzf - --strip-components=1
    ./autogen.sh
    ./configure --prefix=/usr/local/inotify-tools
    make -j$(nproc)
    make install
EOF

# smoke test
RUN test -d /usr/local/inotify-tools


## stage: final
FROM zncdatadev/image/kubedoop-base

COPY --from=builder /build/vector /tmp/vector
COPY --from=builder /usr/local/inotify-tools /usr/local/inotify-tools

# setup inotify-tools
RUN ln -s /usr/local/inotify-tools/bin/inotifywait /usr/local/bin/inotifywait \
    && ln -s /usr/local/inotify-tools/bin/inotifywatch /usr/local/bin/inotifywatch \
    && rpm -ivh /tmp/vector/*.rpm \
    && rm -rf /tmp/vector
