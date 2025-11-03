# syntax=docker/dockerfile:1.17.1@sha256:38387523653efa0039f8e1c89bb74a30504e76ee9f565e25c9a09841f9427b05
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

WORKDIR /kubedoop/bin

ENV PATH="/kubedoop/bin:${PATH}"

RUN <<EOF
    set -ex
    ARCH=$(uname -m)
    ARCH=${ARCH/x86_64/amd64}
    ARCH=${ARCH/aarch64/arm64}

    # Download jq from https://github.com/jqlang/jq/releases
    curl -sSfL \
        https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${ARCH} \
        -o /kubedoop/bin/jq
    chmod +x /kubedoop/bin/jq

    # smoke test jq installation
    jq --version || (echo "jq installation failed" && exit 1)

    # Download yq from https://github.com/mikefarah/yq/releases
    curl -sSfL \
        https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH} \
        -o /kubedoop/bin/yq
    chmod +x /kubedoop/bin/yq

    # smoke test yq installation
    yq --version || (echo "yq installation failed" && exit 1)

    # Download kubectl from https://dl.k8s.io/release
    curl -sSfL \
        https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl \
        -o /kubedoop/bin/kubectl
    chmod +x /kubedoop/bin/kubectl
    # smoke test kubectl installation
    kubectl version --client || (echo "kubectl installation failed" && exit 1)

    chown -R kubedoop:kubedoop /kubedoop
EOF

USER kubedoop

WORKDIR /kubedoop
