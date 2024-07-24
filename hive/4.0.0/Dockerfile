FROM gradle:8 as builder

COPY build.gradle /home/gradle/

RUN gradle download


FROM apache/hive:4.0.0 AS origin


COPY --chown=root:root --from=builder /jars/* /opt/hive/lib/


FROM openjdk:17-jdk-slim AS run

COPY --from=origin /opt/hadoop /opt/hadoop
COPY --from=origin /opt/hive /opt/hive
COPY --from=origin /opt/tez /opt/tez

RUN set -ex; \
    apt-get update; \
    apt-get -y install procps; \
    rm -rf /var/lib/apt/lists/*

ENV HADOOP_HOME=/opt/hadoop \
    HIVE_HOME=/opt/hive \
    TEZ_HOME=/opt/tez \
    HIVE_VER=$HIVE_VERSION

ENV PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:$PATH

COPY --from=origin /entrypoint.sh /
COPY --from=origin /opt/hive/conf $HIVE_HOME/conf
RUN chmod +x /entrypoint.sh

ARG UID=1000
RUN adduser --no-create-home --disabled-login --gecos "" --uid $UID hive && \
    chown hive /opt/tez && \
    chown hive /opt/hive && \
    chown hive /opt/hadoop && \
    chown hive /opt/hive/conf && \
    mkdir -p /opt/hive/data/warehouse && \
    chown hive /opt/hive/data/warehouse && \
    mkdir -p /home/hive/.beeline && \
    chown hive /home/hive/.beeline

USER hive
WORKDIR /zncdata
EXPOSE 10000 10002 9083
ENTRYPOINT ["sh", "-c", "/entrypoint.sh"]