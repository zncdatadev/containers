# syntax=docker/dockerfile:1
# check=error=true

## stage: async-profiler-builder
FROM zncdatadev/image/java-devel AS async-profiler-builder

ARG ASYNC_PROFILER_VERSION

WORKDIR /build

# setup async-profiler
RUN <<EOF
    ARCH=$(uname -m)
    microdnf update

    # build musl-gcc
    # ref: https://github.com/async-profiler/async-profiler/blob/master/Dockerfile
    microdnf install kernel-headers
    mkdir /build/musl-gcc
    pushd /build/musl-gcc
    # https://musl.libc.org/releases/musl-1.2.5.tar.gz
    curl -sSfL \
        https://musl.libc.org/releases/musl-1.2.5.tar.gz \
        | tar xzf - --strip-components=1
    ./configure --disable-shared --prefix=/usr/local/musl
    make -j$(nproc) && make install && make clean
    ln -s /usr/include/{asm,asm-generic,linux} /usr/local/musl/include/
    popd

    # build patchelf
    # ref: https://github.com/NixOS/patchelf?tab=readme-ov-file#compiling-and-testing
    microdnf install autoconf automake
    mkdir /build/patchelf
    pushd /build/patchelf
    # https://github.com/NixOS/patchelf/archive/refs/tags/0.18.0.tar.gz
    curl -sSfL \
        https://github.com/NixOS/patchelf/archive/refs/tags/0.18.0.tar.gz \
        | tar xzf - --strip-components=1
    ./bootstrap.sh
    ./configure
    make -j$(nproc) && make check && make install
    popd

    # build async-profiler
    # ref: https://github.com/async-profiler/async-profiler/blob/master/.github/workflows/test-and-publish-nightly.yml
    mkdir -p /build/async-profiler
    pushd /build/async-profiler
    # https://github.com/async-profiler/async-profiler/archive/refs/tags/v3.0.tar.gz
    curl -sSfL \
        httphttps://github.com/async-profiler/async-profiler/archive/refs/tags/v${ASYNC_PROFILER_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    make CC=/usr/local/musl/bin/musl-gcc release
    # artifact loaction: ./async-profiler-3.0-linux-arm64.tar.gz
    tar zx ./async-profiler-${ASYNC_PROFILER_VERSION}-linux-${ARCH}.tar.gz -C /kubedoop/
    popd
EOF


## stage: builder
FROM zncdatadev/image/java-devel AS java-builder

ARG PRODUCT_VERSION
ARG PROTOBUF_VERSION
ARG JMX_EXPORTER_VERSION
ARG OAUTH2_PROXY_VERSION

WORKDIR /build

COPY kubedoop/jmx/config-${JMX_EXPORTER_VERSION} /kubedoop/jmx

# setup jmx_exporter
RUN <<EOF
    curl -sSfL \
        https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar \
        -o /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar

    ln -s /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /kubedoop/jmx/jmx_prometheus_javaagent.jar
EOF

# Setup protobuf
# ref: https://github.com/apache/hadoop/blob/trunk/dev-support/docker/pkg-resolver/install-protobuf.sh
ENV PROTOBUF_HOME=/opt/protobuf
RUN <<EOF
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
FROM zncdatadev/image/java-base

ARG PRODUCT_VERSION

WORKDIR /kubedoop

COPY --from=async-profiler-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV HADOOP_HOME=/kubedoop/hadoop
ENV HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop" \
    HADOOP_YARN_HOME="${HADOOP_HOME}" \
    HADOOP_MAPRED_HOME="${HADOOP_HOME}" \
    LD_LIBRARY_PATH="${HADOOP_HOME}/lib/native:/usr/lib/jvm/jre/lib/server" \
    PATH="${PATH}:${HADOOP_HOME}/bin"

RUN cat > /etc/profile.d/hadoop.sh <<'EOF'
export CLASSPATH=${CLASSPATH}:$(hadoop classpath --glob)
EOF

USER kubedoop

# smoke test
RUN hadoop version

WORKDIR /kubedoop/hadoop
