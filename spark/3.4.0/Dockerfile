FROM gradle:8 as builder

COPY build.gradle /home/gradle/

RUN gradle download


FROM python:3.10-bullseye

ARG spark_uid=185
ARG DEBIAN_FRONTEND=noninteractive

ARG SPARK_VERSION=3.4.0

USER 0

RUN set -ex && \
    cd /tmp/ && \
    curl -SsLf https://mirrors.ustc.edu.cn/apache/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -O && \
    tar -zxf spark-${SPARK_VERSION}-bin-hadoop3.tgz && \
    mv spark-${SPARK_VERSION}-bin-hadoop3 /opt/spark && \
    cp /opt/spark/kubernetes/dockerfiles/spark/entrypoint.sh /opt/ && \
    cp /opt/spark/kubernetes/dockerfiles/spark/decom.sh /opt/ && \
    rm -rf spark-${SPARK_VERSION}-bin-hadoop3.tgz

RUN set -ex && \
    sed -i -E 's/http:\/\/(deb|security).debian.org/https:\/\/mirrors.cloud.tencent.com/g' /etc/apt/sources.list && \
    apt-get -qq update && \
    ln -s /lib /lib64 && \
    apt install -yqq bash tini libc6 libpam-modules krb5-user libnss3 procps openjdk-11-jre && \
    mkdir -p /opt/spark/examples && \
    mkdir -p /opt/spark/work-dir && \
    touch /opt/spark/RELEASE && \
    rm /bin/sh && \
    ln -sv /bin/bash /bin/sh && \
    echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su && \
    chgrp root /etc/passwd && chmod ug+rw /etc/passwd && \
    rm -rf /var/cache/apt/*

# Alluxio org.alluxio:alluxio-core-client-fs need com.google.guava_guava-31.0.1-jre.jar
# so remive old version.
RUN set -ex && \
    JARS=( \
        "guava-14.0.1.jar" \
        "protobuf-java-2.5.0.jar" \
    ) && \
    for jar in ${JARS[@]}; do \
        jarPath=${SPARK_HOME}/jars/${jar}; \
        echo "Remove jar: ${jarPath}."; \
        rm -rf ${jarPath}; \
    done

COPY --from=builder /jars/*.jar ${SPARK_HOME}/jars/

ENV SPARK_HOME /opt/spark

WORKDIR /opt/spark/work-dir
RUN chmod g+w /opt/spark/work-dir && \
    chmod a+x /opt/decom.sh

ENTRYPOINT [ "/opt/entrypoint.sh" ]

# Specify the User that the actual main process will run as 185
USER ${spark_uid}
