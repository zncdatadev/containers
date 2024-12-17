# syntax=docker/dockerfile:1
# check=error=true

FROM zncdatadev/image/kubedoop-base

ARG PRODUCT_VERSION
ARG KUBECTL_VERSION
ARG JQ_VERSION
ARG YQ_VERSION

RUN <<EOF
    microdnf update

    microdnf install \
        gettext \
        gzip \
        iputils \
        openssl \
        tar \
        zip

    microdnf clean all
    rm -rf /var/cache/yum

EOF

ENV PATH="/kubedoop/bin:${PATH}"

RUN <<EOF
    ARCH=$(uname -m)
    ARCH=${ARCH/x86_64/amd64}
    ARCH=${ARCH/aarch64/arm64}

    # Download jq from https://github.com/jqlang/jq/releases
    curl -sSfL \
        https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${ARCH} \
        -o /kubedoop/bin/jq
    chmod +x /kubedoop/bin/jq

    # Download yq from https://github.com/mikefarah/yq/releases
    curl -sSfL \
        https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH} \
        -o /kubedoop/bin/yq
    chmod +x /kubedoop/bin/yq


    # Download kubectl from https://dl.k8s.io/release
    curl -sSfL \
        https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl \
        -o /kubedoop/bin/kubectl
    chmod +x /kubedoop/bin/kubectl

    chown -R kubedoop:kubedoop /kubedoop
EOF

USER kubedoop

WORKDIR /kubedoop
