# syntax=docker/dockerfile:1

ARG BASE_IMAGE

FROM ${BASE_IMAGE:-quay.io/zncdatadev/kubedata-base:0.0.1-stack0.0.0-dev}

ARG PRODUCT_VERSION
ARG MAVEN_VERSION

RUN <<EOF

    microdnf install hostname \
        which \
        git \
        tzdata-java \
        gcc \
        make \
        cmake \
        gettext \
        cyrus-sasl-devel \
        fuse3-devel \
        krb5-devel \
        openssl-devel \
        zlib-devel \
        unzip \
        zip \
        xz \
        diffutils

    microdnf clean all

EOF

## Setup java
RUN <<EOF
    set -exu
    microdnf install \
        java-${PRODUCT_VERSION}-openjdk-devel
    microdnf clean all
EOF

# debug: RUN java -version

ENV JAVA_HOME=/usr/lib/jvm/jre-${PRODUCT_VERSION}
ENV JAVA_VERSION=${PRODUCT_VERSION}

## Setup maven
ENV MAVEN_VERSION=${MAVEN_VERSION}
ENV MAVEN_HOME=/usr/share/maven

RUN <<EOF

    curl -sSfL \
        https://downloads.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
        | tar xzf - -C /usr/share && \
    ln -s /usr/share/apache-maven-${MAVEN_VERSION} ${MAVEN_HOME} && \
    ln -s ${MAVEN_HOME}/bin/mvn /usr/bin/mvn

EOF

# somke test
# test: RUN mvn --version
