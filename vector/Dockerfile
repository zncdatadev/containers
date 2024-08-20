# syntax=docker/dockerfile:1

ARG KUBEDOOP_BASE_VERSION

## stage: builder
FROM quay.io/zncdatadev/kubedoop-base:${KUBEDOOP_BASE_VERSION}-kubedoop0.0.0-dev AS vector-builder

ARG PRODUCT_VERSION
ARG DOWNLOAD_URL=https://packages.timber.io/vector/${PRODUCT_VERSION}

RUN <<EOF
    set -x

    microdnf update
    microdnf install \
        gzip \
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

    echo "Downloading Vector ${DOWNLOAD_URL}/vector-${PRODUCT_VERSION}-${ARCH}-unknown-linux-musl.tar.gz"

    curl -sSfL --proto '=https' --tlsv1.2 \
        ${DOWNLOAD_URL}/vector-${PRODUCT_VERSION}-${ARCH}-unknown-linux-musl.tar.gz | \
        tar xzf - --strip-components=2

EOF

# smoke test
RUN /build/vector/bin/vector --version

## stage: final
FROM quay.io/zncdatadev/kubedoop-base:${KUBEDOOP_BASE_VERSION}-kubedoop0.0.0-dev


COPY --from=vector-builder /build/vector/bin/ /usr/local/bin/
COPY --from=vector-builder /build/vector/config /etc/vector

# smoke test
RUN vector --version
