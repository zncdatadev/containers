# Golang development environment


FROM zncdatadev/image/kubedoop-base

ARG PRODUCT_VERSION

RUN <<EOF
    microdnf update
    microdnf install \
        cmake \
        cyrus-sasl-devel \
        diffutils \
        fuse-devel \
        gcc \
        gcc-c++ \
        gettext \
        git \
        gzip \
        hostname \
        krb5-devel \
        libcurl-devel \
        make \
        openssl-devel \
        pkg-config \
        tar \
        unzip \
        wget \
        which \
        xz \
        zlib-devel \
        zip

    microdnf clean all
    rm -rf /var/cache/yum
EOF

RUN <<EOF
    set -ex
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    ARCH=${ARCH/x86_64/amd64}
    ARCH=${ARCH/aarch64/arm64}

    # go1.23.2.darwin-arm64.tar.gz
    curl -sSfL --proto '=https' --tlsv1.2 \
        https://go.dev/dl/go${PRODUCT_VERSION}.${OS}-${ARCH}.tar.gz | \
        tar xz -C /usr/local

EOF

ENV GOROOT="/usr/local/go"
ENV PATH="$PATH:$GOROOT/bin"

RUN go version
