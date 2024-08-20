# syntax=docker/dockerfile:1

ARG JAVA_BASE_VERSION
ARG JAVA_DEVEL_VERSION

## stage: java-builder
FROM quay.io/zncdatadev/java-devel:${JAVA_DEVEL_VERSION}-kubedoop0.0.0-dev AS java-builder

ARG PRODUCT_VERSION

WORKDIR /build

RUN <<EOF
    set -ex
    mkdir -p /build/dolphinscheduler-src
    pushd /build/dolphinscheduler-src
    curl -sSfL \
        https://archive.apache.org/dist/dolphinscheduler/${PRODUCT_VERSION}/apache-dolphinscheduler-${PRODUCT_VERSION}-src.tar.gz \
        | tar xzf - --strip-components=1
    chmod +x ./mvnw
    ./mvnw --batch-mode --no-transfer-progress clean package \
        -Dmaven.test.skip \
        -Dmaven.javadoc.skip \
        -Dspotless.skip=true \
        -Prelease

    tar -xzf dolphinscheduler-dist/target/apache-dolphinscheduler-${PRODUCT_VERSION}-bin.tar.gz -C /kubedoop

    ln -s /kubedoop/apache-dolphinscheduler-${PRODUCT_VERSION}-bin /kubedoop/dolphinscheduler
    ls -alh /kubedoop/dolphinscheduler/bin
    popd
EOF


## stage: final

FROM quay.io/zncdatadev/java-base:${JAVA_BASE_VERSION}-kubedoop0.0.0-dev

COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

WORKDIR /kubedoop/dolphinscheduler
USER daemon
