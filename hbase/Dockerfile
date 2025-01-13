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
    set -ex
    ARCH=$(uname -m)
    ARCH="${ARCH/x86_64/x64}"
    ARCH="${ARCH/amd64/x64}"
    ARCH="${ARCH/aarch64/arm64}"

    # build async-profiler
    # https://github.com/async-profiler/async-profiler/releases/download/v3.0/async-profiler-3.0-linux-x64.tar.gz
    curl -sSfL \
        https://github.com/async-profiler/async-profiler/releases/download/v${ASYNC_PROFILER_VERSION}/async-profiler-${ASYNC_PROFILER_VERSION}-linux-${ARCH}.tar.gz \
        | tar -zxf - -C /kubedoop

    ln -s /kubedoop/async-profiler-${ASYNC_PROFILER_VERSION}-linux-${ARCH} /kubedoop/async-profiler
EOF

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

# setup oauth2-proxy
RUN <<EOF
    ARCH=$(uname -m)
    ARCH="${ARCH/x86_64/amd64}"
    ARCH="${ARCH/aarch64/arm64}"

    mkdir /kubedoop/oauth2-proxy
    cd /kubedoop/oauth2-proxy

    curl -sSfL \
        https://github.com/oauth2-proxy/oauth2-proxy/releases/download/v${OAUTH2_PROXY_VERSION}/oauth2-proxy-v${OAUTH2_PROXY_VERSION}.linux-${ARCH}.tar.gz \
        | tar xzf - --strip-components=1

    # smoke test
    /kubedoop/oauth2-proxy/oauth2-proxy --version
EOF

WORKDIR /build
COPY /kubedoop/patches /build/patches
RUN <<EOF
    set -ex
    mkdir -p /build/hbase-src
    pushd /build/hbase-src
    curl -sSfL \
        https://github.com/apache/hbase/archive/refs/tags/rel/${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    /build/patches/apply_patches.sh /build/patches/${PRODUCT_VERSION}

    mvn \
        --batch-mode \
        --no-transfer-progress \
        -Dhadoop.profile=3.0 \
        -Dhadoop-three.version=${HADOOP_VERSION} \
        clean \
        install \
        assembly:single \
        -DskipTests \
        -Dcheckstyle.skip=true \
        -Prelease

    tar -xzf hbase-assembly/target/hbase-${PRODUCT_VERSION}-bin.tar.gz -C /kubedoop
    ln -s /kubedoop/hbase-${PRODUCT_VERSION} /kubedoop/hbase
    popd

    # cleanup source
    rm -rf /build/hbase-src

    # cleanup cache
    rm -rf /root/.m2
    rm -rf /root/.npm

EOF

# smoke test
RUN /kubedoop/hbase/bin/hbase version


# ## stage: hbase-operator-tools-builder
# FROM zncdatadev/image/java-devel AS hbase-operator-tools-builder

# ARG PRODUCT_VERSION
# ARG HBASE_OPERATOR_TOOLS_VERSION
# ARG HBASE_THIRDPARTY_VERSION

# WORKDIR /build

# # setup hbase-operator-tools
# RUN <<EOF
#     set -ex
#     mkdir -p /build/hbase-operator-tools-src
#     pushd /build/hbase-operator-tools-src

#     # if HBASE_OPERATOR_TOOLS_VERSION contains '-', it is a snapshot version, we need to
#     # split it. the first part is version, the second part is the commit hash
#     # use the commit hash to download the source code.
#     if [[ ${HBASE_OPERATOR_TOOLS_VERSION} == *-* ]]; then
#         version=$(echo ${HBASE_OPERATOR_TOOLS_VERSION} | cut -d '-' -f 1)
#         sha=$(echo ${HBASE_OPERATOR_TOOLS_VERSION} | cut -d '-' -f 2)
#         HBASE_OPERATOR_TOOLS_VERSION="${version}-SNAPSHOT"
#         curl -sSfL \
#             https://github.com/apache/hbase-operator-tools/archive/${sha}.tar.gz \
#             | tar xzf - --strip-components=1
#     else
#         curl -sSfL \
#             https://github.com/apache/hbase-operator-tools/archive/refs/tags/rel/${HBASE_OPERATOR_TOOLS_VERSION}.tar.gz \
#             | tar xzf - --strip-components=1
#     fi

#     # build hbase-operator-tools
#     mvn \
#         --no-transfer-progress \
#         -Dhbase.version=${PRODUCT_VERSION} \
#         -Dhbase-thirdparty.version=${HBASE_THIRDPARTY_VERSION} \
#         -DskipTests \
#         package assembly:single

#     tar -xzf hbase-operator-tools-assembly/target/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION}-bin.tar.gz -C /kubedoop
#     ln -s /kubedoop/hbase-operator-tools-${HBASE_OPERATOR_TOOLS_VERSION} /kubedoop/hbase-operator-tools
#     popd

#     # cleanup source
#     rm -rf /build/hbase-operator-tools-src

#     # cleanup cache
#     rm -rf /root/.m2
# EOF


# ## stage: phoenix-builder
# FROM zncdatadev/image/java-devel AS phoenix-builder

# ARG PRODUCT_VERSION
# ARG HADOOP_VERSION
# ARG PHOENIX_VERSION
# ARG HBASE_PROFILE_VERSION

# WORKDIR /build
# # setup phoenix
# RUN <<EOF
#     set -ex
#     mkdir -p /build/phoenix-src
#     pushd /build/phoenix-src

#     # Phonix repoisotry is https://github.com/apache/phoenix,
#     # release download url is https://github.com/apache/phoenix/archive/refs/tags/5.2.1.tar.gz
#     # If PHONIX_VERSION contains '-', it is a snapshot version, we need to
#     # split it. the first part is version, the second part is the commit hash
#     # use the commit hash to download the source code.
#     if [[ ${PHOENIX_VERSION} == *-* ]]; then
#         version=$(echo ${PHOENIX_VERSION} | cut -d '-' -f 1)
#         sha=$(echo ${PHOENIX_VERSION} | cut -d '-' -f 2)
#         PHOENIX_VERSION="${version}-SNAPSHOT"
#         curl -sSfL \
#             https://github.com/apache/phoenix/archive/${sha}.tar.gz \
#             | tar xzf - --strip-components=1
#     else
#         curl -sSfL \
#             https://github.com/apache/phoenix/archive/refs/tags/${PHOENIX_VERSION}.tar.gz \
#             | tar xzf - --strip-components=1
#     fi

#     # build phoenix
#     mvn \
#         --no-transfer-progress \
#         -Dhbase.version=${PRODUCT_VERSION} \
#         -Dhbase.profile=${HBASE_PROFILE_VERSION} \
#         -Dhadoop.version=${HADOOP_VERSION} \
#         -DskipTests \
#         -Dcheckstyle.skip=true \
#         clean \
#         package

#     mkdir /kubedoop/phoenix-${HBASE_PROFILE_VERSION}-${PHOENIX_VERSION}-bin
#     tar -xzf phoenix-assembly/target/phoenix-hbase-*-bin.tar.gz -C /kubedoop/phoenix-${HBASE_PROFILE_VERSION}-${PHOENIX_VERSION}-bin --strip-components=1
#     ln -s /kubedoop/phoenix-${HBASE_PROFILE_VERSION}-${PHOENIX_VERSION}-bin /kubedoop/phoenix
#     popd

#     # cleanup source
#     rm -rf /build/phoenix-src

#     # cleanup cache
#     rm -rf /root/.m2
# EOF


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
# # setup hbase-operator-tools
# COPY --from=hbase-operator-tools-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
# # setup phoenix
# COPY --from=phoenix-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
# setup hadoop-s3
COPY --from=hadoop-s3-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

RUN find /kubedoop/hadoop/share/ -name *.jar | grep 'aws' | xargs -I {} ln -s {} /kubedoop/hbase/lib/ \
    && ln -s /kubedoop/phoenix/phoenix-server-hbase-${HBASE_PROFILE_VERSION}.jar /kubedoop/hbase/lib/

ENV HBASE_HOME=/kubedoop/hbase

ENV HBASE_CONFIG_DIR="${HBASE_HOME}/conf" \
    PATH="${PATH}:${HBASE_HOME}/bin" \
    ASYNC_PROFILER_HOME=/kubedoop/async-profiler

WORKDIR /kubedoop/hbase

USER kubedoop

CMD ["hbase", "master", "start"]
