# syntax=docker/dockerfile:1

ARG KUBEDOOP_BASE_VERSION

FROM quay.io/zncdatadev/kubedoop-base:${KUBEDOOP_BASE_VERSION}-kubedoop0.0.0-dev 

ARG PRODUCT_VERSION
ARG MAVEN_VERSION

RUN <<EOF
    # install jdk 22 from epel in ubi9
    rpm --install --replacepkgs https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    microdnf update
    microdnf install \
        cmake \
        cyrus-sasl-devel \
        diffutils \
        fuse-devel \
        gcc \
        gcc-c++ \
        gettext \
        git \
        hostname \
        krb5-devel \
        libcurl-devel \
        make \
        openssl-devel \
        patch \
        tar \
        wget \
        which \
        xz \
        zlib-devel \
        unzip \
        zip

    microdnf clean all
EOF

## Setup java
RUN <<EOF
    microdnf install java-${PRODUCT_VERSION}-openjdk-devel
    microdnf clean all
EOF

# smoke test
RUN java -version

ENV JAVA_HOME=/usr/lib/jvm/jre-${PRODUCT_VERSION}
ENV JAVA_VERSION=${PRODUCT_VERSION}

## Setup maven
ENV MAVEN_VERSION=${MAVEN_VERSION}
ENV MAVEN_HOME=/usr/share/maven

RUN <<EOF
    curl -sSfL \
        https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
        | tar xzf - -C /usr/share && \
    ln -s /usr/share/apache-maven-${MAVEN_VERSION} ${MAVEN_HOME} && \
    ln -s ${MAVEN_HOME}/bin/mvn /usr/bin/mvn

EOF

# somke test
RUN mvn --version
