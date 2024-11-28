ARG JAVA_VERSION
ARG JAVA_DEVEL_VERSION

## stage: builder
FROM quay.io/zncdatadev/java-devel:${JAVA_DEVEL_VERSION}-kubedoop0.0.0-dev AS java-builder

ARG PRODUCT_VERSION
ARG PROTOBUF_VERSION
ARG JMX_EXPORTER_VERSION
ARG OAUTH2_PROXY_VERSION

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

# Setup protobuf
# ref: https://github.com/apache/hadoop/blob/trunk/dev-support/docker/pkg-resolver/install-protobuf.sh
ENV PROTOBUF_HOME=/opt/protobuf
RUN <<EOF
    set -e
    mkdir -p /build/protobuf-src
    pushd /build/protobuf-src
    PROTOBUF_LANGUAGE_VERSION=$PROTOBUF_VERSION

    if [ "$(echo -e "$PROTOBUF_VERSION\n21.12" | sort -V | head -n 1)" = "$PROTOBUF_VERSION" ]; then
        PROTOBUF_LANGUAGE_VERSION=java-$PROTOBUF_VERSION
    fi

    curl -sSfL \
        https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protobuf-${PROTOBUF_LANGUAGE_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    ./configure --prefix=${PROTOBUF_HOME}
    make -j$(nproc)
    make install
    ln -s ${PROTOBUF_HOME}/bin/protoc /usr/bin/protoc
    popd
EOF

# smoke test
RUN protoc --version

# Setup boost
# ref: https://github.com/apache/hadoop/blob/trunk/dev-support/docker/pkg-resolver/install-boost.sh
RUN <<EOF
    rpm --install --replacepkgs https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    microdnf update
    microdnf install boost1.78-devel
    microdnf clean all
EOF

COPY kubedoop /build/

RUN <<EOF
    set -ex
    mkdir -p /build/hadoop-src
    pushd /build/hadoop-src
    curl -sSfL \
        https://github.com/apache/hadoop/archive/refs/tags/rel/release-${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    /build/patches/apply_patches.sh /build/patches/${PRODUCT_VERSION}
    mvn --no-transfer-progress clean package -Pdist,native -pl '!hadoop-tools/hadoop-pipes,!hadoop-yarn-project,!hadoop-mapreduce-project,!hadoop-minicluster' -Drequire.fuse=true -DskipTests -Dmaven.javadoc.skip=true

    cp -r hadoop-dist/target/hadoop-${PRODUCT_VERSION} /kubedoop/hadoop-${PRODUCT_VERSION}
    cp hadoop-hdfs-project/hadoop-hdfs-native-client/target/main/native/fuse-dfs/fuse_dfs /kubedoop/hadoop-${PRODUCT_VERSION}/bin

    ln -s /kubedoop/hadoop-${PRODUCT_VERSION} /kubedoop/hadoop
    popd
EOF

# smoke test
RUN HADOOP_HOME=/kubedoop/hadoop HADOOP_YARN_HOME=/kubedoop/hadoop HADOOP_MAPRED_HOME=/kubedoop/hadoop /kubedoop/hadoop/bin/hadoop version

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

RUN <<EOF
set -ex
ARCH=$(uname -m)
ARCH="${ARCH/x86_64/amd64}"
ARCH="${ARCH/aarch64/arm64}"

mkdir /kubedoop/oauth2-proxy
cd /kubedoop/oauth2-proxy

curl -sSfL \
    https://github.com/oauth2-proxy/oauth2-proxy/releases/download/v${OAUTH2_PROXY_VERSION}/oauth2-proxy-v${OAUTH2_PROXY_VERSION}.linux-${ARCH}.tar.gz \
    | tar xzf - --strip-components=1

EOF

# smoke test
RUN /kubedoop/oauth2-proxy/oauth2-proxy --version

## stage: final
FROM quay.io/zncdatadev/java-base:${JAVA_VERSION}-kubedoop0.0.0-dev

ARG PRODUCT_VERSION

WORKDIR /kubedoop

COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV HADOOP_HOME=/kubedoop/hadoop
ENV HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop" \
    HADOOP_YARN_HOME="${HADOOP_HOME}" \
    HADOOP_MAPRED_HOME="${HADOOP_HOME}" \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${HADOOP_HOME}/lib/native:/usr/lib/jvm/jre/lib/server" \
    PATH="${PATH}:${HADOOP_HOME}/bin"

RUN <<EOT
    set -e
    cat > /etc/profile.d/hadoop.sh <<'EOF'
export CLASSPATH=${CLASSPATH}:$(hadoop classpath --glob)
EOF

EOT

USER kubedoop

# smoke test
RUN hadoop version

WORKDIR /kubedoop/hadoop
