# syntax=docker/dockerfile:1


ARG JAVA_VERSION
ARG JAVA_DEVEL_VERSION

## stage: trino-storage-connector-builder
FROM quay.io/zncdatadev/java-devel:${JAVA_DEVEL_VERSION}-kubedoop0.0.0-dev AS storage-connector-builder

ARG PRODUCT_VERSION
ARG STORAGE_CONNECTOR_VERSION

RUN <<EOF
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
FROM quay.io/zncdatadev/java-devel:${JAVA_DEVEL_VERSION}-kubedoop0.0.0-dev AS java-builder

ARG PRODUCT_VERSION
ARG STORAGE_CONNECTOR_VERSION
ARG JMX_EXPORTER_VERSION

WORKDIR /build


COPY kubedoop/jmx/config-${JMX_EXPORTER_VERSION} /kubedoop/jmx

# setup jmx_exporter
RUN <<EOF
    set -e
    # check JMX_EXPORTER_VERSION
    if [ -n "${JMX_EXPORTER_VERSION}" ]; then
        curl -sSfL \
            https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar \
            -o /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar

        ln -s /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /kubedoop/jmx/jmx_prometheus_javaagent.jar
    else
        echo "JMX_EXPORTER_VERSION is not set"
    fi
EOF

# build trino
RUN <<EOF
    set -ex
    mkdir -p /build/trino-src
    pushd /build/trino-src
    # https://github.com/trinodb/trino/archive/refs/tags/454.tar.gz
    curl -sSfL \
        https://github.com/trinodb/trino/archive/refs/tags/${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1

    ./mvnw --no-transfer-progress package -DskipTests -Dmaven.gitcommitid.skip=true --projects="!docs,!core/trino-server-rpm"

    tar -xzf core/trino-server/target/trino-server-${PRODUCT_VERSION}.tar.gz -C /kubedoop
    ln -s /kubedoop/trino-server-${PRODUCT_VERSION} /kubedoop/trino-server

    cp client/trino-cli/target/trino-cli-${PRODUCT_VERSION}-executable.jar /kubedoop/trino-server/bin/trino-cli
    popd
EOF

COPY --from=storage-connector-builder --chown=kubedoop:kubedoop /build/trino-storage-src/target/trino-storage-${STORAGE_CONNECTOR_VERSION} /kubedoop/trino-server/plugin/trino-storage-${STORAGE_CONNECTOR_VERSION}

# smoke test
RUN microdnf install python && microdnf clean all && /kubedoop/trino-server/bin/launcher status || [ $? -eq 3 ]

# Fix log4j vulnerability
RUN <<EOF
    set -e
    ARCH=$(uname -m)
    ARCH="${ARCH/amd64/x86_64}"
    ARCH="${ARCH/aarch64/arm64}"
    curl -sSfL -o /usr/local/bin/log4shell \
        https://github.com/lunasec-io/lunasec/releases/download/v1.6.1-log4shell/log4shell_1.6.1-log4shell_Linux_${ARCH}
    chmod +x /usr/local/bin/log4shell
    /usr/local/bin/log4shell patch --backup --force-patch --json hadoop-${PRODUCT_VERSION}
EOF


## stage: final
FROM quay.io/zncdatadev/java-base:${JAVA_VERSION}-kubedoop0.0.0-dev

RUN <<EOF
    set -e
    microdnf update
    microdnf install \
        python

    microdnf clean all
EOF

COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV TRINO_HOME=/kubedoop/trino-server
ENV PATH="${PATH}:${TRINO_HOME}/bin"

WORKDIR /kubedoop/trino-server
USER kubedoop

# smoke test
RUN launcher status || [ $? -eq 3 ]

CMD ["launcher", "run"]
