# syntax=docker/dockerfile:1
# check=error=true


# stage: zookeeper-builder
FROM zncdatadev/image/java-devel AS zookeeper-builder

ARG PRODUCT_VERSION
ARG JMX_EXPORTER_VERSION

WORKDIR /build

# setup jmx_exporter
COPY kubedoop/jmx/config /kubedoop/jmx
RUN <<EOF
    curl -sSfL \
        https://github.com/prometheus/jmx_exporter/releases/download/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar \
        -o /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar

    ln -s /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /kubedoop/jmx/jmx_prometheus_javaagent.jar
EOF

# build zookeeper
RUN --mount=type=cache,target=/root/.m2 <<EOF
    mkdir -p /build/zookeeper-src
    pushd /build/zookeeper-src
    curl -sSfL \
        https://github.com/apache/zookeeper/archive/refs/tags/release-${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    mvn --batch-mode --no-transfer-progress -pl "!zookeeper-client/zookeeper-client-c" clean install checkstyle:check spotbugs:check -DskipTests -Pfull-build
    tar -xzf zookeeper-assembly/target/apache-zookeeper-${PRODUCT_VERSION}-bin.tar.gz -C /kubedoop
    mv /kubedoop/apache-zookeeper-${PRODUCT_VERSION}-bin /kubedoop/apache-zookeeper-${PRODUCT_VERSION}
    ln -s /kubedoop/apache-zookeeper-${PRODUCT_VERSION} /kubedoop/zookeeper
    popd

    # smoke test
    /kubedoop/zookeeper/bin/zkServer.sh version

    # cleanup source
    rm -rf /build/zookeeper-src
EOF

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


## final stage
FROM zncdatadev/image/java-base

ARG PRODUCT_VERSION

WORKDIR /kubedoop

COPY --from=zookeeper-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV ZOOKEEPER_HOME=/kubedoop/zookeeper
ENV PATH="$ZOOKEEPER_HOME/bin:$PATH"

WORKDIR /kubedoop/zookeeper
USER kubedoop

CMD ["bin/zkServer.sh", "start-foreground", "config/zoo_sample.cfg"]
