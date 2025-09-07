# syntax=docker/dockerfile:1
# check=error=true


FROM zncdatadev/image/kubedoop-base

ARG PRODUCT_VERSION

RUN <<EOT
    set -ex
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
        maven \
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

    # Due to the maven default dependency jdk17, so two versions of jdk are installed if the PRODUCT_VERSION is not 17.
    # Use alternatives to set the default Java version

    # Determine Java path based on version
    if [ "${PRODUCT_VERSION}" -ge "24" ]; then
        EXPECTED_JAVA_PATH="/usr/lib/jvm/java-${PRODUCT_VERSION}-temurin-jdk"
    else
        EXPECTED_JAVA_PATH="/usr/lib/jvm/temurin-${PRODUCT_VERSION}-jdk"
    fi

    # Check current java version and reset alternatives if needed
    CURRENT_JAVA_VERSION=$(alternatives --display java | grep "link currently points to" | grep -oE "/usr/lib/jvm/(temurin|java)-[0-9]+-.*jdk")

    if [ "$CURRENT_JAVA_VERSION" != "$EXPECTED_JAVA_PATH" ]; then
        echo "Configuring Java alternatives for version ${PRODUCT_VERSION} at path ${EXPECTED_JAVA_PATH}"
        # Install alternatives if not exists
        alternatives --install /usr/bin/java java ${EXPECTED_JAVA_PATH}/bin/java 1
        alternatives --install /usr/bin/javac javac ${EXPECTED_JAVA_PATH}/bin/javac 1

        # Set alternatives
        alternatives --set java ${EXPECTED_JAVA_PATH}/bin/java
        alternatives --set javac ${EXPECTED_JAVA_PATH}/bin/javac
    fi

    # smoke test
    JAVA_VERSION_OUTPUT=$(java -version 2>&1)
    if [ "${PRODUCT_VERSION}" != "8" ]; then
        echo "$JAVA_VERSION_OUTPUT" | grep -q "openjdk version \"${PRODUCT_VERSION}\." || {
            echo "ERROR: Expected Java ${PRODUCT_VERSION}, but got:"
            echo "$JAVA_VERSION_OUTPUT"
            exit 1
        }
    else
        echo "$JAVA_VERSION_OUTPUT" | grep -q "openjdk version \"1\.${PRODUCT_VERSION}\." || {
            echo "ERROR: Expected Java 1.${PRODUCT_VERSION}, but got:"
            echo "$JAVA_VERSION_OUTPUT"
            exit 1
        }
    fi
EOT

ENV JAVA_HOME=/usr/lib/jvm/temurin-${PRODUCT_VERSION}-jdk
ENV JAVA_VERSION=${PRODUCT_VERSION}

# Mitigation for CVE-2021-44228 (Log4Shell)
# This variable is supported as of Log4j version 2.10 and
# disables the vulnerable feature
ENV LOG4J_FORMAT_MSG_NO_LOOKUPS=true
