# syntax=docker/dockerfile:1

ARG JAVA_VERSION
ARG JAVA_DEVEL_VERSION
ARG HADOOP_VERSION

## stage: hbase-builder
FROM quay.io/zncdatadev/java-devel:${JAVA_DEVEL_VERSION}-kubedoop0.0.0-dev AS java-builder

ARG PRODUCT_VERSION
ARG HADOOP_VERSION
# 2.6 exports jmx and prometheus metrics by default
ARG JMX_EXPORTER_VERSION=""
ARG OAUTH2_PROXY_VERSION

# setup jmx_exporter
WORKDIR /kubedoop/jmx
COPY kubedoop/jmx /build/jmx
RUN <<EOF
    set -ex
    # check JMX_EXPORTER_VERSION
    if [ -n "${JMX_EXPORTER_VERSION}" ]; then
        curl -sSfL \
            https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar \
            -o /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar
        
        ln -s /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /kubedoop/jmx/jmx_prometheus_javaagent.jar
        
        # copy jmx_exporter config
        cp /build/jmx/config-${JMX_EXPORTER_VERSION}/* /kubedoop/jmx/
    else
        echo "JMX_EXPORTER_VERSION is not set"
    fi
EOF

WORKDIR /build
COPY /kubedoop/ /build/

RUN <<EOF
    set -e
    mkdir -p /build/hbase-src
    pushd /build/hbase-src
    curl -sSfL \
        https://archive.apache.org/dist/hbase/${PRODUCT_VERSION}/hbase-${PRODUCT_VERSION}-src.tar.gz \
        | tar xzf - --strip-components=1
    /build/patches/apply_patches.sh /build/patches/${PRODUCT_VERSION}

    mvn --batch-mode --no-transfer-progress -Dhadoop.profile=3.0 -Dhadoop-three.version=${HADOOP_VERSION} clean install assembly:single -DskipTests -Dcheckstyle.skip=true -Prelease

    tar -xzf hbase-assembly/target/hbase-${PRODUCT_VERSION}-bin.tar.gz -C /kubedoop
    ln -s /kubedoop/hbase-${PRODUCT_VERSION} /kubedoop/hbase
    popd
    
EOF

# smoke test
RUN /kubedoop/hbase-${PRODUCT_VERSION}/bin/hbase version

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


## stage: hbase-operator-tools-builder
FROM quay.io/zncdatadev/java-devel:${JAVA_DEVEL_VERSION}-kubedoop0.0.0-dev AS hbase-operator-tools-builder

ARG PRODUCT_VERSION
ARG HBASE_OPERATOR_TOOLS_VERSION
ARG HBASE_THIRDPARTY_VERSION

WORKDIR /build

RUN <<EOF
    set -ex
    mkdir -p /build/hbase-operator-tools-src
    pushd /build/hbase-operator-tools-src

    # if HBASE_OPERATOR_TOOLS_VERSION contains '-', it is a snapshot version, we need to
    # split it. the first part is version, the second part is the commit hash
    # use the commit hash to download the source code.
    if [[ ${HBASE_OPERATOR_TOOLS_VERSION} == *-* ]]; then
        version=$(echo ${HBASE_OPERATOR_TOOLS_VERSION} | cut -d '-' -f 1)
        sha=$(echo ${HBASE_OPERATOR_TOOLS_VERSION} | cut -d '-' -f 2)
        HBASE_OPERATOR_TOOLS_VERSION="${version}-SNAPSHOT"
        curl -sSfL \
            https://github.com/apache/hbase-operator-tools/archive/${sha}.tar.gz \
            | tar xzf - --strip-components=1
    else
        curl -sSfL \
            https://archive.apache.org/dist/hbase/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION}/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION}-src.tar.gz \
            | tar xzf - --strip-components=1
    fi
    mvn \
        --batch-mode \
        --no-transfer-progress \
        -Dhbase.version=${PRODUCT_VERSION} \
        -Dhbase-thirdparty.version=${HBASE_THIRDPARTY_VERSION} \
        -DskipTests \
        package assembly:single
    
    tar -xzf hbase-operator-tools-assembly/target/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION}-bin.tar.gz -C /kubedoop
    ln -s /kubedoop/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION} /kubedoop/hbase-operator-tools
    popd
EOF

## stage: final
FROM quay.io/zncdatadev/java:${JAVA_VERSION}-kubedoop0.0.0-dev

ARG PRODUCT_VERSION

RUN <<EOF
    set -e
    microdnf update
    microdnf install \
        gzip \
        python \
        python-pip \
        tar \
        zip
    microdnf clean all
EOF

WORKDIR /kubedoop

COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
COPY --from=hbase-operator-tools-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV HBASE_HOME=/kubedoop/hbase
ENV HBASE_CONFIG_DIR="${HBASE_HOME}/conf" \
    PATH="${PATH}:${HBASE_HOME}/bin"

WORKDIR /kubedoop/hbase

USER kubedoop

# smoke test
RUN hbase version

CMD ["hbase", "master", "start"]
