FROM gradle:8 as builder

COPY build.gradle /home/gradle/

RUN gradle download


FROM apache/hive:4.0.0

COPY --chown=root:root --from=builder /jars/* /opt/hive/lib/
