# Golang development environment

ARG KUBEDOOP_BASE_VERSION

FROM quay.io/zncdatadev/kubedoop-base:${KUBEDOOP_BASE_VERSION}-kubedoop0.0.0-dev 

ARG PRODUCT_VERSION

RUN <<EOF
    microdnf update
    microdnf install \
        cmake \
        cyrus-sasl \
        diffutils \
        gettext \
        git \
        gzip
        hostname \
        krb5-workstation \
        openssl \
        pkg-config \
        tar \
        unzip \
        which \
        xz \
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

ENV PATH=$PATH:/usr/local/go/bin

RUN go version
