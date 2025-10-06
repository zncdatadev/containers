# syntax=docker/dockerfile:1.17.1@sha256:38387523653efa0039f8e1c89bb74a30504e76ee9f565e25c9a09841f9427b05
# check=error=true


## stage: hive-builder
FROM zncdatadev/image/java-devel AS hive-builder

ARG PRODUCT_VERSION
ARG JMX_EXPORTER_VERSION

WORKDIR /build

COPY kubedoop/jmx/config /kubedoop/jmx

# setup jmx_exporter
RUN <<EOF
    # check JMX_EXPORTER_VERSION
    if [ -n "${JMX_EXPORTER_VERSION}" ]; then
        curl -sSfL \
            https://github.com/prometheus/jmx_exporter/releases/download/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar \
            -o /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar

        ln -s /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /kubedoop/jmx/jmx_prometheus_javaagent.jar
    else
        echo "JMX_EXPORTER_VERSION is not set"
    fi
EOF

COPY kubedoop/ /build/

RUN --mount=type=cache,target=/root/.m2 <<EOF
    set -ex
    mkdir -p /build/hive-src
    pushd /build/hive-src
    curl -sSfL \
        https://github.com/apache/hive/archive/refs/tags/rel/release-${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    /build/patches/apply_patches.sh /build/patches/${PRODUCT_VERSION}

    # When the version is less than 4.0.0, we need to build the standalone-metastore
    if [ "$(printf '%s\n' "4.0.0" "${PRODUCT_VERSION}" | sort -V | head -n1)" != "4.0.0" ]; then
        mvn --no-transfer-progress clean package -DskipTests --projects standalone-metastore
        cp -r standalone-metastore/target/apache-hive-metastore-${PRODUCT_VERSION}-bin/apache-hive-metastore-${PRODUCT_VERSION}-bin /kubedoop/
    else
        # https://issues.apache.org/jira/browse/HIVE-20451
        mvn --no-transfer-progress clean package -DskipTests --projects standalone-metastore
        tar -xzf standalone-metastore/target/apache-hive-standalone-metastore-${PRODUCT_VERSION}-src.tar.gz -C /build
        pushd /build/apache-hive-standalone-metastore-${PRODUCT_VERSION}-src

        mvn --batch-mode --no-transfer-progress clean package -DskipTests --projects metastore-server
        tar -xf metastore-server/target/apache-hive-standalone-metastore-server-${PRODUCT_VERSION}-bin.tar.gz -C /kubedoop
        # unarchive to /kubedoop/apache-hive-metastore-${PRODUCT_VERSION}-bin
        popd
    fi

    cp /build/bin/start-metastore /kubedoop/apache-hive-metastore-${PRODUCT_VERSION}-bin/bin/

    ln -s /kubedoop/apache-hive-metastore-${PRODUCT_VERSION}-bin /kubedoop/hive-metastore
    popd

    # cleanup source
    rm -rf /build/hive-src
EOF

COPY kubedoop/bin/start-metastore /kubedoop/hive-metastore/bin/

# smoke test
RUN /kubedoop/hive-metastore/bin/start-metastore --help


## stage: hadoop
FROM zncdatadev/image/hadoop AS hadoop


## stage: final
FROM zncdatadev/image/java-base

ARG PRODUCT_VERSION
ARG HADOOP_VERSION

WORKDIR /kubedoop

COPY --from=hive-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
# When start the hive-metastore, it will try to load the hadoop configuration from the classpath.
COPY --from=hadoop --chown=kubedoop:kubedoop /kubedoop/hadoop-${HADOOP_VERSION} /kubedoop/hadoop-${HADOOP_VERSION}

RUN <<EOF
    ln -s /kubedoop/hadoop-${HADOOP_VERSION} /kubedoop/hadoop
    find /kubedoop/hadoop/share/ -name *.jar | grep 'aws\|azure' | xargs -I {} ln -s {} /kubedoop/hive-metastore/lib/
EOF

ENV HADOOP_HOME=/kubedoop/hadoop \
    HIVE_HOME=/kubedoop/hive-metastore
ENV PATH="${PATH}:${HIVE_HOME}/bin:${HADOOP_HOME}/bin" \
    HADOOP_YARN_HOME="${HADOOP_HOME}" \
    HADOOP_MAPRED_HOME="${HADOOP_HOME}"

USER kubedoop

WORKDIR /kubedoop/hive-metastore

# smoke test
RUN base --service metastore --help || [ $? -eq 1 ]
