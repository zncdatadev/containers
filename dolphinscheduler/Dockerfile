# syntax=docker/dockerfile:1

ARG JAVA_VERSION
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
        https://github.com/apache/dolphinscheduler/archive/refs/tags/${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    chmod +x ./mvnw
    ./mvnw --batch-mode --no-transfer-progress clean package \
        -Dmaven.test.skip \
        -Dmaven.javadoc.skip \
        -Dspotless.skip=true \
        -Prelease

    tar -xzf dolphinscheduler-dist/target/apache-dolphinscheduler-${PRODUCT_VERSION}-bin.tar.gz -C /kubedoop

    # set +x to avoid permission denied for sub-projects
    find /kubedoop/apache-dolphinscheduler-${PRODUCT_VERSION}-bin -maxdepth 2 -type d -name "bin" -exec chmod +x -R {} \;

    ln -s /kubedoop/apache-dolphinscheduler-${PRODUCT_VERSION}-bin /kubedoop/dolphinscheduler
    popd
EOF


## stage: final

FROM quay.io/zncdatadev/java-base:${JAVA_VERSION}-kubedoop0.0.0-dev

COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

USER kubedoop

WORKDIR /kubedoop/dolphinscheduler
