# syntax=docker/dockerfile:1.8

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4-1194

COPY kubedoop/dnf.conf /etc/dnf/dnf.conf

RUN <<EOF
    microdnf update -y
    microdnf install \
        iputils \
        less \
        procps \
        tar \
        xz

    groupadd -g 1001 --system kubedoop 
    useradd \
        --no-log-init \
        --gid 1001 \
        --uid 1001 \
        --create-home \
        --home-dir /kubedoop \
        kubedoop

    microdnf clean all
EOF

ENV PATH=$PATH:/kubedoop

# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
# https://specs.opencontainers.org/image-spec/annotations/#pre-defined-annotation-keys
LABEL org.opencontainers.image.authors="ZNCDataDev Team" \
    org.opencontainers.image.url="https://zncdata.dev" \
    org.opencontainers.image.vendor="ZNCDataDev" \
    org.opencontainers.image.licenses="Apache-2.0"
