# syntax=docker/dockerfile:1

ARG KUBEDOOP_BASE_VERSION

FROM quay.io/zncdatadev/kubedoop-base:${KUBEDOOP_BASE_VERSION}-kubedoop0.0.0-dev 

ARG PRODUCT_VERSION
ARG MAVEN_VERSION

RUN <<EOT
    # https://adoptium.net/en-GB/installation/linux/#_centosrhelfedora_instructions
    cat <<EOF > /etc/yum.repos.d/adoptium.repo
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/${DISTRIBUTION_NAME:-$(. /etc/os-release; echo $ID)}/\$releasever/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF

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
        gzip \
        hostname \
        krb5-devel \
        libcurl-devel \
        make \
        openssl-devel \
        patch \
        pkg-config \
        tar \
        temurin-${PRODUCT_VERSION}-jdk \
        tzdata-java \
        unzip \
        wget \
        which \
        xz \
        zlib-devel \
        zip

    microdnf clean all
    rm -rf /var/cache/yum
EOT

# smoke test
RUN java -version

ENV JAVA_HOME=/usr/lib/jvm/temurin-${PRODUCT_VERSION}-jdk
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

# Mitigation for CVE-2021-44228 (Log4Shell)
# This variable is supported as of Log4j version 2.10 and
# disables the vulnerable feature
ENV LOG4J_FORMAT_MSG_NO_LOOKUPS=true
