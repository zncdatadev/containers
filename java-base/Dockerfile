# syntax=docker/dockerfile:1
# check=error=true

ARG VECTOR_VERSION=0.41.1

## stage: final
FROM quay.io/zncdatadev/vector:${VECTOR_VERSION}-kubedoop0.0.0-dev

ARG PRODUCT_VERSION

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
        krb5-workstation \
        temurin-${PRODUCT_VERSION}-jre \
        tzdata-java

    microdnf clean all
    rm -rf /var/cache/yum
EOT

# smoke test
RUN java -version

ENV JAVA_HOME=/usr/lib/jvm/temurin-${PRODUCT_VERSION}-jre
ENV JAVA_VERSION=${PRODUCT_VERSION}

# Mitigation for CVE-2021-44228 (Log4Shell)
# This variable is supported as of Log4j version 2.10 and
# disables the vulnerable feature
ENV LOG4J_FORMAT_MSG_NO_LOOKUPS=true
