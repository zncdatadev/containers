# syntax=docker/dockerfile:1
# check=error=true

## stage: trino-storage-connector-builder
FROM zncdatadev/image/java-devel AS storage-connector-builder

ARG PRODUCT_VERSION
ARG STORAGE_CONNECTOR_VERSION

RUN --mount=type=cache,target=/root/.m2 <<EOF
    set -ex
    mkdir -p /build/trino-storage-src
    pushd /build/trino-storage-src
    # https://github.com/snowlift/trino-storage/archive/refs/tags/v454.tar.gz
    curl -sSfL \
        https://github.com/snowlift/trino-storage/archive/refs/tags/v${STORAGE_CONNECTOR_VERSION}.tar.gz \
        | tar xzf - --strip-components=1

    ./mvnw --no-transfer-progress versions:set -DnewVersion=${STORAGE_CONNECTOR_VERSION}
    ./mvnw --no-transfer-progress package -DskipTests -Dmaven.gitcommitid.skip=true

    # all jars artifact location: /build/trino-storage-src/target/trino-storage-451/
EOF


## stage: trino-builder
FROM zncdatadev/image/java-devel AS trino-builder

ARG PRODUCT_VERSION
ARG STORAGE_CONNECTOR_VERSION
ARG JMX_EXPORTER_VERSION

WORKDIR /build

COPY kubedoop/jmx/config /kubedoop/jmx

# setup jmx_exporter
RUN <<EOF
    curl -sSfL \
        https://github.com/prometheus/jmx_exporter/releases/download/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar \
        -o /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar

    ln -s /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /kubedoop/jmx/jmx_prometheus_javaagent.jar
EOF

# build trino
RUN --mount=type=cache,target=/root/.m2 <<EOF
    mkdir -p /build/trino-src
    pushd /build/trino-src
    # https://github.com/trinodb/trino/archive/refs/tags/454.tar.gz
    curl -sSfL \
        https://github.com/trinodb/trino/archive/refs/tags/${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1

    # Build trino with error checking
    echo "Starting Trino build..."
    if ! ./mvnw --batch-mode \
        --no-transfer-progress \
        package \
        -DskipTests \
        -Dmaven.gitcommitid.skip=true \
        --projects='!docs,!core/trino-server-rpm' \
        -e ; then
        echo "ERROR: Trino build failed"
        exit 1
    fi
    echo "Trino build completed successfully"

    TRINO_SERVER_BINARY="core/trino-server/target/trino-server-${PRODUCT_VERSION}.tar.gz"
    TRINO_SERVER_HOME="/kubedoop/trino-server-${PRODUCT_VERSION}"

    if [ ! -f "${TRINO_SERVER_BINARY}" ]; then
        echo "Error: Trino server binary not found: ${TRINO_SERVER_BINARY}"
        ls -alh core/trino-server/target/
        exit 1
    fi

    tar -xzvf core/trino-server/target/trino-server-${PRODUCT_VERSION}.tar.gz -C /kubedoop || {
        echo "Error: Failed to extract Trino server binary"
        exit 1
    }

    # create symlink
    if [ ! -d "${TRINO_SERVER_HOME}" ]; then
        echo "Error: Trino server home directory not found: ${TRINO_SERVER_HOME}"
        ls -la /kubedoop/
        exit 1
    fi

    ln -sf /kubedoop/trino-server-${PRODUCT_VERSION} /kubedoop/trino-server

    cp client/trino-cli/target/trino-cli-${PRODUCT_VERSION}-executable.jar /kubedoop/trino-server/bin/trino-cli
    popd

    # cleanup source
    rm -rf /build/trino-src

    # smoke test - check if trino-cli works
    /kubedoop/trino-server/bin/trino-cli --version || {
        echo "ERROR: Trino CLI smoke test failed"
        ls -alh /kubedoop/trino-server/bin/
        exit 1
    }
    echo "Trino CLI smoke test passed"
EOF

# smoke test - enhanced with status check and error handling
RUN <<EOF
    microdnf update
    # trino launcher needs python
    microdnf install python
    microdnf clean all

    # smoke test
    echo "Running Trino launcher smoke test..."
    LAUNCHER="/kubedoop/trino-server-${PRODUCT_VERSION}/bin/launcher"

    if [ ! -f "$LAUNCHER" ]; then
        echo "ERROR: Trino launcher not found at: $LAUNCHER"
        ls -la "${TRINO_SERVER_HOME}/bin/" || echo "bin directory not found"
        exit 1
    fi

    # 运行状态检查
    echo "Checking Trino launcher status..."
    status_output=$("$LAUNCHER" status 2>&1)
    exit_code=$?

    if [ $exit_code -eq 3 ]; then
        echo "SUCCESS: Trino launcher status check passed (server is not running, as expected)"
    else
        echo "ERROR: Unexpected launcher status. Exit code: $exit_code"
        echo "Status output:"
        echo "$status_output"
        exit 1
    fi
EOF

COPY --from=storage-connector-builder --chown=kubedoop:kubedoop /build/trino-storage-src/target/trino-storage-${STORAGE_CONNECTOR_VERSION} /kubedoop/trino-server/plugin/trino-storage-${STORAGE_CONNECTOR_VERSION}

# Fix log4j vulnerability
RUN <<EOF
    ARCH=$(uname -m)
    ARCH="${ARCH/amd64/x86_64}"
    ARCH="${ARCH/aarch64/arm64}"
    curl -sSfL -o /usr/local/bin/log4shell \
        https://github.com/lunasec-io/lunasec/releases/download/v1.6.1-log4shell/log4shell_1.6.1-log4shell_Linux_${ARCH}
    chmod +x /usr/local/bin/log4shell
    /usr/local/bin/log4shell patch --backup --force-patch --json hadoop-${PRODUCT_VERSION}
EOF


## stage: final
FROM zncdatadev/image/java-base

RUN <<EOF
    set -e
    microdnf update
    microdnf install \
        python

    microdnf clean all
EOF

COPY --from=trino-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV TRINO_HOME=/kubedoop/trino-server
ENV PATH="${TRINO_HOME}/bin:${PATH}"

WORKDIR /kubedoop/trino-server
USER kubedoop

CMD ["launcher", "run"]
