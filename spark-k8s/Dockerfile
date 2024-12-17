# syntax=docker/dockerfile:1
# check=error=true


FROM docker.io/library/gradle:8 AS gradle-builder

ARG PRODUCT_VERSION
ARG JMX_EXPORTER_VERSION

WORKDIR /build

RUN <<EOT
    cat > build.gradle <<EOF
apply plugin: 'base'

repositories {
    mavenLocal()
    mavenCentral()
}

configurations {
    toCopy
}

dependencies {
    toCopy('org.apache.spark:spark-hadoop-cloud_2.13:${PRODUCT_VERSION}') {
        exclude group: 'org.slf4j', module: 'slf4j-api' // exclude slf4j-api to avoid conflict
    }
    toCopy 'com.fasterxml.jackson.dataformat:jackson-dataformat-xml:2.14.2'
}

task download(type: Copy) {
    from configurations.toCopy
    into '/jars'
}

EOF

    # show dependencies graph
    gradle --no-daemon dependencies

    # download dependencies
    gradle download --no-daemon

EOT


## stage: java-builder
FROM zncdatadev/image/java-devel AS java-builder

ARG PRODUCT_VERSION
ARG HADOOP_VERSION
ARG JMX_EXPORTER_VERSION
ARG OAUTH2_PROXY_VERSION

WORKDIR /build

# setup jmx_exporter
COPY kubedoop/jmx/config-${JMX_EXPORTER_VERSION} /kubedoop/jmx
RUN <<EOF
    curl -sSfL \
    https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar \
    -o /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar

    ln -s /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /kubedoop/jmx/jmx_prometheus_javaagent.jar
EOF

# build spark
RUN --mount=type=cache,target=/root/.m2 <<EOF
    set -e
    mkdir -p /build/spark-src
    pushd /build/spark-src
    curl -sSfL \
        https://github.com/apache/spark/archive/refs/tags/v${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    ./dev/make-distribution.sh \
        -Dhadoop.version=${HADOOP_VERSION} \
        -Dmaven.javadoc.skip=true \
        -DskipTests \
        -Phadoop-3 \
        -Pkubernetes \
        -Phive \
        -Phive-thriftserver

    cp -r dist /kubedoop/spark-${PRODUCT_VERSION}

    ln -s /kubedoop/spark-${PRODUCT_VERSION} /kubedoop/spark
    ln -s /kubedoop/spark/jars/spark-examples_*.jar /kubedoop/spark/examples.jar
    popd

    # smoke test
    /kubedoop/spark/bin/spark-shell --version

    # cleanup source
    rm -rf /build/spark-src
EOF

COPY --from=gradle-builder /jars/ /kubedoop/spark/jars/

# setup oauth2-proxy
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
ARG PYTHON_VERSION

RUN <<EOF
    set -e
    microdnf update
    microdnf install \
        procps \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip \
        java-${JAVA_VERSION}-openjdk-devel \
        zip

    microdnf clean all
    rm -rf /var/cache/yum

    ln -s /usr/bin/python${PYTHON_VERSION} /usr/bin/python
    ln -s /usr/bin/pip-${PYTHON_VERSION} /usr/bin/pip
EOF

COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV SPARK_HOME=/kubedoop/spark
ENV PATH="${SPARK_HOME}/bin:${PATH}" \
    PYSPARK_PYTHON=/usr/bin/python \
    PYTHONPATH="${SPARK_HOME}/python:${PYTHONPATH}"

WORKDIR /kubedoop/spark

USER kubedoop

# smoke test
RUN source /etc/profile.d/spark.sh && spark-shell --version
