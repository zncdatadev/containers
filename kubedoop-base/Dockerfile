# syntax=docker/dockerfile:1


# registry.redhat.io/ubi9/ubi-minimal:9.6-1755695350
# https://catalog.redhat.com/en/software/containers/ubi9/ubi-minimal/615bd9b4075b022acc111bf5?image=68a5d252653f4281018c6e90#get-this-image
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:2f06ae0e6d3d9c4f610d32c480338eef474867f435d8d28625f2985e8acde6e8

COPY kubedoop/dnf.conf /etc/dnf/dnf.conf

RUN <<EOF
    microdnf update -y
    microdnf install \
        findutils \
        iputils \
        less \
        procps \
        tar

    groupadd -g 1001 --system kubedoop
    useradd \
        --no-log-init \
        --gid 1001 \
        --uid 1001 \
        --create-home \
        --home-dir /kubedoop \
        kubedoop

    microdnf clean all
    rm -rf /var/cache/yum
EOF

ENV PATH=$PATH:/kubedoop

# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
# https://specs.opencontainers.org/image-spec/annotations/#pre-defined-annotation-keys
LABEL org.opencontainers.image.authors="ZNCDataDev Team" \
    org.opencontainers.image.url="https://zncdata.dev" \
    org.opencontainers.image.vendor="ZNCDataDev" \
    org.opencontainers.image.licenses="Apache-2.0"
