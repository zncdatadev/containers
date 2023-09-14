FROM gradle:8 as alluxio-builder

COPY build.gradle /home/gradle/

RUN gradle download


FROM apache/hive:4.0.0-beta-1

COPY --chown=root:root --from=alluxio-builder /jars/* /opt/hive/lib/
