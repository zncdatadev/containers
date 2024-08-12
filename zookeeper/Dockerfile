ARG BASE_IMAGE

FROM ${BASE_IMAGE}

ARG PRODUCT_VERSION

RUN curl -L -o /tmp/apache-zookeeper-${PRODUCT_VERSION}-bin.tar.gz \
    https://downloads.apache.org/zookeeper/zookeeper-${PRODUCT_VERSION}/apache-zookeeper-${PRODUCT_VERSION}-bin.tar.gz \
    && tar -xzf /tmp/apache-zookeeper-${PRODUCT_VERSION}-bin.tar.gz -C /opt \
    && rm -f /tmp/apache-zookeeper-${PRODUCT_VERSION}-bin.tar.gz
