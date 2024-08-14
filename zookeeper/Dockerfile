# syntax=docker/dockerfile:1

ARG BASE_IMAGE

FROM ${BASE_IMAGE} AS builder

ARG PRODUCT_VERSION
WORKDIR /build

# curl -f -L -o log4shell https://github.com/lunasec-io/lunasec/releases/download/v1.6.1-log4shell/log4shell_1.6.1-log4shell_Linux_${ARCH} && \
# chmod +x log4shell && \
# ./log4shell patch --backup --force-patch --json /opt/apache-zookeeper

RUN <<EOF
    ARCH=$(uname -m) 
    ARCH="${ARCH/amd64/x86_64}" 
    ARCH="${ARCH/aarch64/arm64}"
    curl -sSfL \
        https://downloads.apache.org/zookeeper/zookeeper-${PRODUCT_VERSION}/apache-zookeeper-${PRODUCT_VERSION}-bin.tar.gz \
        | tar xzf - 
    
    curl -sSfL -o /usr/local/bin/log4shell \
        https://github.com/lunasec-io/lunasec/releases/download/v1.6.1-log4shell/log4shell_1.6.1-log4shell_Linux_${ARCH}
    chmod +x /usr/local/bin/log4shell
    /usr/local/bin/log4shell patch --backup --force-patch --json apache-zookeeper-${PRODUCT_VERSION}-bin

EOF

## final stage
FROM ${BASE_IMAGE}

ARG PRODUCT_VERSION

WORKDIR /kubedoop

COPY --chown=kubedoop:kubedoop --from=builder /build/apache-zookeeper-${PRODUCT_VERSION}-bin apache-zookeeper-${PRODUCT_VERSION}-bin

# debug: RUN ls -l /kubedoop

ENV ZOOKEEPER_HOME=/kubedoop/zookeeper
ENV PATH=$ZOOKEEPER_HOME/bin:$PATH

WORKDIR /kubedoop/zookeeper

USER kubedoop

CMD ["bin/zkServer.sh", "start-foreground", "config/zoo_sample.cfg"]
