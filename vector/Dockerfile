ARG BASE_IMAGE

FROM ${BASE_IMAGE:-quay.io/zncdatadev/kubedata-base:0.0.1-stack0.0.0-dev}

ARG PRODUCT_VERSION
ARG DOWNLOAD_URL=https://packages.timber.io/vector/${PRODUCT_VERSION}

RUN ARCH=$(uname -m) ARCH="${ARCH/amd64/x86_64}" ARCH="${ARCH/arm64/aarch64}" && \
    mkdir -p /tmp/vector && \
    echo "Downloading Vector ${DOWNLOAD_URL}/vector-${PRODUCT_VERSION}-${ARCH}-unknown-linux-musl.tar.gz" && \
    curl -sSfL --proto '=https' --tlsv1.2 ${DOWNLOAD_URL}/vector-${PRODUCT_VERSION}-${ARCH}-unknown-linux-musl.tar.gz | \
    tar xzf - -C /tmp/vector --strip-components=2

RUN mv /tmp/vector/bin/vector /usr/local/bin/vector && \
    chmod +x /usr/local/bin/vector && \
    mkdir /etc/vector && \
    mv /tmp/vector/config/* /etc/vector/ && \
    rm -rf /tmp/vector
