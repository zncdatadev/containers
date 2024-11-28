
ARG JAVA_VERSION
ARG JAVA_DEVEL_VERSION
ARG HADOOP_VERSION


## stage: java-builder
FROM quay.io/zncdatadev/java-devel:${JAVA_DEVEL_VERSION}-kubedoop0.0.0-dev AS java-builder

ARG PRODUCT_VERSION
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

COPY kubedoop/ /build/

RUN <<EOF
    set -ex
    mkdir -p /build/hive-src
    pushd /build/hive-src
    curl -sSfL \
        https://github.com/apache/hive/archive/refs/tags/rel/release-${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    /build/patches/apply_patches.sh /build/patches/${PRODUCT_VERSION}
    mvn --no-transfer-progress clean package -DskipTests --projects standalone-metastore

    cp -r standalone-metastore/target/apache-hive-metastore-${PRODUCT_VERSION}-bin/apache-hive-metastore-${PRODUCT_VERSION}-bin /kubedoop/
    mv /kubedoop/apache-hive-metastore-${PRODUCT_VERSION}-bin /kubedoop/apache-hive-metastore-${PRODUCT_VERSION}
    cp /build/bin/start-metastore /kubedoop/apache-hive-metastore-${PRODUCT_VERSION}/bin/

    ln -s /kubedoop/apache-hive-metastore-${PRODUCT_VERSION} /kubedoop/hive-metastore
    popd
EOF

COPY kubedoop/bin/start-metastore /kubedoop/hive-metastore/bin/

# smoke test
RUN /kubedoop/hive-metastore/bin/start-metastore --help

FROM quay.io/zncdatadev/hadoop:${HADOOP_VERSION}-kubedoop0.0.0-dev AS hadoop


## stage: final
FROM ${BASE_IMAGE:-quay.io/zncdatadev/java-base:11-kubedoop0.0.0-dev}

ARG PRODUCT_VERSION
ARG HADOOP_VERSION

WORKDIR /kubedoop

COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
# When start the hive-metastore, it will try to load the hadoop configuration from the classpath.
COPY --from=hadoop --chown=kubedoop:kubedoop /kubedoop/hadoop-${HADOOP_VERSION} /kubedoop/hadoop-${HADOOP_VERSION}

RUN <<EOF
    set -e
    ln -s /kubedoop/hadoop-${HADOOP_VERSION} /kubedoop/hadoop
    find /kubedoop/hadoop/share/ -name *.jar | grep 'aws\|azure' | xargs -I {} ln -s {} /kubedoop/hive-metastore/lib/
EOF

ENV HADOOP_HOME=/kubedoop/hadoop \
    HIVE_HOME=/kubedoop/hive-metastore
ENV HADOOP_YARN_HOME="${HADOOP_HOME}" \
    HADOOP_MAPRED_HOME="${HADOOP_HOME}" \
    PATH="${PATH}:${HIVE_HOME}/bin:${HADOOP_HOME}/bin"

USER kubedoop

WORKDIR /kubedoop/hive-metastore

# smoke test
RUN base --service metastore --help || [ $? -eq 1 ]
