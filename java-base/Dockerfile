# syntax=docker/dockerfile:1

ARG VECTOR_VERSION

## stage: final
FROM quay.io/zncdatadev/vector:${VECTOR_VERSION}-kubedoop0.0.0-dev

ARG PRODUCT_VERSION

RUN <<EOF
    # install jdk 22 from epel in ubi9
    rpm --install --replacepkgs https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    microdnf update
    microdnf install tzdata-java krb5-workstation
    microdnf clean all
EOF

RUN <<EOF
    microdnf update
    microdnf install java-${PRODUCT_VERSION}-openjdk-headless
    microdnf clean all
EOF

# smoke test
RUN java -version

ENV JAVA_HOME=/usr/lib/jvm/jre-${PRODUCT_VERSION}
ENV JAVA_VERSION=${PRODUCT_VERSION}

# Mitigation for CVE-2021-44228 (Log4Shell)
# This variable is supported as of Log4j version 2.10 and
# disables the vulnerable feature
ENV LOG4J_FORMAT_MSG_NO_LOOKUPS=true
