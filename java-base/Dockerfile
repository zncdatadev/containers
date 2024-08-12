ARG BASE_IMAGE

FROM ${BASE_IMAGE:-quay.io/zncdatadev/kubedata-base:0.0.1-stack0.0.0-dev}

ARG PRODUCT_VERSION

# RUN dnf -y install --setopt=install_weak_deps=False \
#     java-${PRODUCT_VERSION}-openjdk-headless \
#     tzdata-java \
#     krb5-workstation \
#     && dnf clean all

RUN <<EOF

    microdnf install java-${PRODUCT_VERSION}-openjdk-headless \
        tzdata-java \
        krb5-workstation

    microdnf clean all

EOF

ENV JAVA_HOME=/usr/lib/jvm/jre-${PRODUCT_VERSION}
ENV JAVA_VERSION=${PRODUCT_VERSION}

# Mitigation for CVE-2021-44228 (Log4Shell)
# This variable is supported as of Log4j version 2.10 and
# disables the vulnerable feature
ENV LOG4J_FORMAT_MSG_NO_LOOKUPS=true
