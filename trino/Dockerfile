FROM gradle:8 as alluxio-builder

COPY build.gradle /home/gradle/

RUN gradle download


FROM trinodb/trino:424

COPY --chown=trino:trino --from=alluxio-builder /jars/* /usr/lib/trino/plugin/iceberg/
