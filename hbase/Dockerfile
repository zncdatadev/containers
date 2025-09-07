# syntax=docker/dockerfile:1
# check=error=true


## stage: hbase-builder
FROM zncdatadev/image/java-devel AS hbase-builder

ARG PRODUCT_VERSION
ARG HADOOP_VERSION
ARG ASYNC_PROFILER_VERSION
# 2.6 exports jmx and prometheus metrics by default
ARG JMX_EXPORTER_VERSION=""
ARG OAUTH2_PROXY_VERSION

# setup async-profiler
RUN <<EOF
    ARCH=$(uname -m)
    ARCH="${ARCH/x86_64/x64}"
    ARCH="${ARCH/amd64/x64}"
    ARCH="${ARCH/aarch64/arm64}"

    # build async-profiler
    # https://github.com/async-profiler/async-profiler/releases/download/v3.0/async-profiler-3.0-linux-x64.tar.gz
    ASYNC_PROFILER_DIR="/kubedoop/async-profiler-${ASYNC_PROFILER_VERSION}-linux-${ARCH}"
    SOURCE_URL="https://github.com/async-profiler/async-profiler/releases/download/v${ASYNC_PROFILER_VERSION}/async-profiler-${ASYNC_PROFILER_VERSION}-linux-${ARCH}.tar.gz"
    echo "Downloading async-profiler from: ${SOURCE_URL}"
    curl -sSfL "${SOURCE_URL}" | tar -zxf - -C /kubedoop


    # Verify installation and create symlink
    if [ ! -f "${ASYNC_PROFILER_DIR}/build/libasyncProfiler.so" ]; then
        echo "ERROR: async-profiler library not found in ${ASYNC_PROFILER_DIR}"
        ls -la "${ASYNC_PROFILER_DIR}/build/" || echo "build directory not found"
        exit 1
    fi
    echo "Successfully installed async-profiler to: ${ASYNC_PROFILER_DIR}"
    ln -sf "${ASYNC_PROFILER_DIR}" /kubedoop/async-profiler
EOF

# setup jmx_exporter
WORKDIR /kubedoop/jmx
COPY kubedoop/jmx /build/jmx
RUN <<EOF
    # check JMX_EXPORTER_VERSION
    if [ -n "${JMX_EXPORTER_VERSION}" ]; then
        JMX_JAR="/kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar"
        SOURCE_URL="https://github.com/prometheus/jmx_exporter/releases/download/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar"
        echo "Downloading jmx_exporter from: ${SOURCE_URL}"
        curl -sSfL "${SOURCE_URL}" -o ${JMX_JAR}

        # Verify installation and create symlink
        if [ ! -f "${JMX_JAR}" ]; then
            echo "ERROR: jmx_exporter jar not found at ${JMX_JAR}"
            exit 1
        fi

        echo "Successfully installed jmx_exporter to: ${JMX_JAR}"
        ln -s ${JMX_JAR} /kubedoop/jmx/jmx_prometheus_javaagent.jar

        # copy jmx_exporter config
        cp /build/jmx/config/* /kubedoop/jmx/
    else
        echo "JMX_EXPORTER_VERSION is not set"
    fi
EOF

# setup oauth2-proxy
RUN <<EOF
    ARCH=$(uname -m)
    ARCH="${ARCH/x86_64/amd64}"
    ARCH="${ARCH/aarch64/arm64}"

    mkdir /kubedoop/oauth2-proxy
    cd /kubedoop/oauth2-proxy

    SOURCE_URL="https://github.com/oauth2-proxy/oauth2-proxy/releases/download/v${OAUTH2_PROXY_VERSION}/oauth2-proxy-v${OAUTH2_PROXY_VERSION}.linux-${ARCH}.tar.gz"
    echo "Downloading oauth2-proxy from: ${SOURCE_URL}"
    curl -sSfL "${SOURCE_URL}" | tar xzf - --strip-components=1

    # smoke test
    /kubedoop/oauth2-proxy/oauth2-proxy --version
EOF

WORKDIR /build
COPY /kubedoop/patches /build/patches
RUN <<EOF
    mkdir -p /build/hbase-src
    pushd /build/hbase-src

    PATCHES_PATH=/build/patches

    SOURCE_URL="https://github.com/apache/hbase/archive/refs/tags/rel/${PRODUCT_VERSION}.tar.gz"

    # Download and extract source
    echo "Downloading HBase from: ${SOURCE_URL}"
    curl -sSfL "${SOURCE_URL}" | tar xzf - --strip-components=1

    # Apply patches if exists
    PATCH_DIR="${PATCHES_PATH}/${PATCH_PATH}"
    if [ -d "${PATCH_DIR}" ]; then
        ${PATCHES_PATH}/apply_patches.sh ${PATCH_DIR}
    fi

    mvn \
        --no-transfer-progress \
        -Dhadoop.profile=3.0 \
        -Dhadoop-three.version=${HADOOP_VERSION} \
        clean \
        install \
        assembly:single \
        -DskipTests \
        -Dcheckstyle.skip=true \
        -Prelease

    # Install HBase binary
    HBASE_BINARY="hbase-assembly/target/hbase-${PRODUCT_VERSION}-bin.tar.gz"
    HBASE_HOME="/kubedoop/hbase-${PRODUCT_VERSION}"

    if [ ! -f "${HBASE_BINARY}" ]; then
        echo "ERROR: HBase binary not found at ${HBASE_BINARY}"
        ls -la hbase-assembly/target/
        exit 1
    fi

    tar -xzf "${HBASE_BINARY}" -C /kubedoop || {
        echo "ERROR: Failed to extract HBase binary"
        exit 1
    }

    if [ ! -d "${HBASE_HOME}" ]; then
        echo "ERROR: HBase directory not found at ${HBASE_HOME}"
        ls -la /kubedoop/
        exit 1
    fi

    ln -sf "${HBASE_HOME}" /kubedoop/hbase
    popd

    # cleanup source
    rm -rf /build/hbase-src

    # cleanup cache
    rm -rf /root/.m2
    rm -rf /root/.npm

EOF

# smoke test
RUN /kubedoop/hbase/bin/hbase version


## stage: hbase-operator-tools-builder
FROM zncdatadev/image/java-devel AS hbase-operator-tools-builder

ARG PRODUCT_VERSION
ARG HBASE_OPERATOR_TOOLS_VERSION
ARG HBASE_THIRDPARTY_VERSION

WORKDIR /build
COPY /kubedoop/patches /build/patches
# setup hbase-operator-tools
RUN <<EOF
    mkdir -p /build/hbase-operator-tools-src
    pushd /build/hbase-operator-tools-src

    PATCHES_PATH=/build/patches

    # Parse version and sha if needed
    PATCH_PATH="${HBASE_OPERATOR_TOOLS_VERSION}"
    if [[ ${HBASE_OPERATOR_TOOLS_VERSION} == *-* ]]; then
        version=${HBASE_OPERATOR_TOOLS_VERSION%%-*}
        sha=${HBASE_OPERATOR_TOOLS_VERSION#*-}
        PATCH_PATH="${version}-${sha}"
        HBASE_OPERATOR_TOOLS_VERSION="${version}-SNAPSHOT"

        # Download from specific commit
        SOURCE_URL="https://github.com/apache/hbase-operator-tools/archive/${sha}.tar.gz"
    else
        # Download from release tag
        SOURCE_URL="https://github.com/apache/hbase-operator-tools/archive/refs/tags/rel/${HBASE_OPERATOR_TOOLS_VERSION}.tar.gz"
    fi

    # Download and extract source
    echo "Downloading hbase-operator-tools from: ${SOURCE_URL}"
    curl -sSfL "${SOURCE_URL}" | tar xzf - --strip-components=1

    # Apply patches if exists
    PATCHES_DIR="${PATCHES_PATH}/hbase-operator-tools/${PATCH_PATH}"
    if [ -d "${PATCHES_DIR}" ]; then
        echo "Applying patches from: ${PATCHES_DIR}"
        ${PATCHES_PATH}/apply_patches.sh "${PATCHES_DIR}" || exit 1
    fi

    # build hbase-operator-tools
    mvn \
        --no-transfer-progress \
        -Dhbase.version=${PRODUCT_VERSION} \
        -Dhbase-thirdparty.version=${HBASE_THIRDPARTY_VERSION} \
        -DskipTests \
        package assembly:single

    HBASE_OPERATOR_TOOLS_BINARY="hbase-operator-tools-assembly/target/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION}-bin.tar.gz"
    HBASE_OPERATOR_TOOLS_HOME="/kubedoop/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION}"

    # Check if the binary exists
    if [ ! -f "${HBASE_OPERATOR_TOOLS_BINARY}" ]; then
        echo "ERROR: HBase Operator Tools binary not found at ${HBASE_OPERATOR_TOOLS_BINARY}"
        ls -la /kubedoop/
        exit 1
    fi

    tar -xzf "${HBASE_OPERATOR_TOOLS_BINARY}" -C /kubedoop || {
        echo "ERROR: Failed to extract HBase Operator Tools binary"
        exit 1
    }

    if [ ! -d "${HBASE_OPERATOR_TOOLS_HOME}" ]; then
        echo "ERROR: HBase Operator Tools directory not found at ${HBASE_OPERATOR_TOOLS_HOME}"
        ls -la /kubedoop/
        exit 1
    fi

    ln -sf /kubedoop/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION} /kubedoop/hbase-operator-tools
    popd

    # cleanup source
    rm -rf /build/hbase-operator-tools-src

    # cleanup cache
    rm -rf /root/.m2
EOF


## stage: hadoop-builder
FROM zncdatadev/image/hadoop AS hadoop


## stage: hadoop-s3-builder
FROM zncdatadev/image/java-devel AS hadoop-s3-builder

ARG HADOOP_VERSION

COPY --from=hadoop \
    /kubedoop/hadoop/share/hadoop/tools/lib/aws-java-sdk-bundle-*.jar \
    /kubedoop/hadoop/share/hadoop/tools/lib/hadoop-aws-${HADOOP_VERSION}.jar \
    /kubedoop/hadoop/share/hadoop/tools/lib/


## stage: final
FROM zncdatadev/image/java-base

ARG PRODUCT_VERSION
ARG HBASE_PROFILE_VERSION

RUN <<EOF
    microdnf update
    microdnf install \
        findutils \
        gzip \
        python \
        python-pip \
        tar \
        zip

    microdnf clean all
    rm -rf /var/cache/yum
EOF

WORKDIR /kubedoop

COPY --from=hbase-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
# setup hbase-operator-tools
COPY --from=hbase-operator-tools-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
# setup hadoop-s3
COPY --from=hadoop-s3-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

RUN find /kubedoop/hadoop/share/ -name *.jar | grep 'aws' | xargs -I {} ln -s {} /kubedoop/hbase/lib/

ENV HBASE_HOME=/kubedoop/hbase

ENV HBASE_CONFIG_DIR="${HBASE_HOME}/conf" \
    PATH="${PATH}:${HBASE_HOME}/bin" \
    ASYNC_PROFILER_HOME=/kubedoop/async-profiler

WORKDIR /kubedoop/hbase

USER kubedoop

CMD ["hbase", "master", "start"]
