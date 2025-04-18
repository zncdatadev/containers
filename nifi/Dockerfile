# syntax=docker/dockerfile:1
# check=error=true


# stage: nifi-builder
FROM zncdatadev/image/java-devel AS nifi-builder

ARG PRODUCT_VERSION

WORKDIR /build

# Build apache nifi from github tag
RUN --mount=type=cache,target=/root/.m2 --mount=type=cache,target=/root/.npm <<EOF
    mkdir -p /build/nifi-src
    pushd /build/nifi-src
    # Download apache nifi source from https://github.com/apache/nifi/releases/tag/rel%2Fnifi-1.27.0
    curl -sSfL \
        https://github.com/apache/nifi/archive/refs/tags/rel/nifi-${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1

    # Build apache nifi use mvnw
    ./mvnw \
        clean \
        install \
        --batch-mode \
        --no-transfer-progress \
        -Dmaven.javadoc.skip=true \
        -DskipTests \
        --activate-profiles include-iceberg,include-hadoop-aws,include-hadoop-azure,include-hadoop-gc

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

COPY --from=nifi-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV NIFI_HOME=/kubedoop/nifi
ENV PATH="${NIFI_HOME}/bin:${PATH}"

WORKDIR /kubedoop/nifi

CMD ["nifi.sh", "run"]
