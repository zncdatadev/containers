# syntax=docker/dockerfile:1
# check=error=true

## stage: dolphin-builder
FROM zncdatadev/image/java-devel AS dolphin-builder

ARG PRODUCT_VERSION

WORKDIR /build

RUN --mount=type=cache,target=/root/.m2 --mount=type=cache,target=/root/.pnpm-store <<EOF
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

    # cleanup source
    rm -rf /build/dolphinscheduler-src
EOF

# smoke test
RUN test -f /kubedoop/dolphinscheduler/bin/dolphinscheduler-daemon.sh


## stage: final
FROM zncdatadev/image/java-base

COPY --from=dolphin-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

USER kubedoop

WORKDIR /kubedoop/dolphinscheduler
