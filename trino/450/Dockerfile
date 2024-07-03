FROM gradle:8 as builder

COPY build.gradle /home/gradle/

RUN gradle download


FROM trinodb/trino:450

COPY --chown=trino:trino --from=builder /jars/* /usr/lib/trino/plugin/iceberg/
