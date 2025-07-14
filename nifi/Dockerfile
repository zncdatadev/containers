# syntax=docker/dockerfile:1
# check=error=true


# stage: nifi-builder
FROM zncdatadev/image/java-devel AS nifi-builder

ARG PRODUCT_VERSION
ARG MAVEN_VERSION=3.9.8

WORKDIR /build

# Setup maven
RUN <<EOF
    set -euo pipefail
    mkdir -p /build/maven
    # Download maven binary from https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz
    curl -sSfL \
        https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
        | tar -zxf - --strip-components=1 -C /build/maven

    # Create symlink for maven
    ln -sf /build/maven/bin/mvn /usr/bin/mvn

    # smoke test
    mvn --version | grep "Apache Maven ${MAVEN_VERSION}" || exit 1
EOF

COPY kubedoop /build/

# Build apache nifi from github tag
RUN --mount=type=cache,target=/root/.m2 --mount=type=cache,target=/root/.npm <<EOF
    set -euo pipefail
    mkdir -p /build/nifi-src
    pushd /build/nifi-src
    # Download apache nifi source from https://github.com/apache/nifi/releases/tag/rel%2Fnifi-1.27.0
    curl -sSfL \
        https://github.com/apache/nifi/archive/refs/tags/rel/nifi-${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1

    /build/apply_patches.sh /build/patches/${PRODUCT_VERSION}

    # Build apache nifi use mvnw
    ./mvnw \
        clean \
        install \
        --batch-mode \
        --no-transfer-progress \
        -Dmaven.javadoc.skip=true \
        -DskipTests \
        --activate-profiles include-hadoop,include-hadoop-aws,include-hadoop-azure,include-hadoop-gcp

    # unzip nifi binary
    unzip -q \
        nifi-assembly/target/nifi-${PRODUCT_VERSION}-bin.zip \
        -d /kubedoop

    ln -s /kubedoop/nifi-${PRODUCT_VERSION} /kubedoop/nifi

    # Rm nifi doc
    rm -rf /kubedoop/nifi/docs
    popd

    # smoke test
    /kubedoop/nifi/bin/nifi.sh --help

    # cleanup source
    rm -rf /build/nifi-src

EOF


## Final stage
FROM zncdatadev/image/java-base

RUN <<EOF
    microdnf update
    microdnf install \
        gettext \
        git \
        python3-pip \

    microdnf clean all
    rm -rf /var/cache/yum

    pip install --no-cache-dir \
        nipyapi==0.19.1 \
        bcrypt
EOF

COPY --from=nifi-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV NIFI_HOME=/kubedoop/nifi
ENV PATH="${NIFI_HOME}/bin:${PATH}"

WORKDIR /kubedoop/nifi

CMD ["nifi.sh", "run"]
