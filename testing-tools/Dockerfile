# syntax=docker/dockerfile:1
# check=error=true

FROM python:3.12-slim-bullseye

ARG PRODUCT_VERSION
ARG KEYCLOAK_VERSION

# Disable interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

RUN <<EOF
    groupadd --gid 1000 --system kubedoop
    useradd \
        --system \
        --gid 1000 \
        --uid 1000 \
        --create-home \
        --home-dir /kubedoop \
        kubedoop
EOF

RUN <<EOF
    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        diffutils \
        gzip \
        jq \
        krb5-user \
        kubernetes-client \
        libkrb5-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        openssl \
        pkg-config \
        tar \
        zip \
        unzip \
        openjdk-11-jdk-headless
    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF

COPY python/requirements.txt /kubedoop/

RUN curl -sSfL https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz | tar xzC /kubedoop && \
    ln -s /kubedoop/keycloak-${KEYCLOAK_VERSION} /kubedoop/keycloak

RUN <<EOF
    pip install --no-cache-dir --upgrade pip
    pip install --no-cache-dir -r /kubedoop/requirements.txt

    chown -R kubedoop:kubedoop /kubedoop
EOF

ENV PATH=$PATH:/kubedoop/keycloak/bin:/kubedoop/.local/bin \
    PRODUCT_VERSION=${PRODUCT_VERSION}

USER kubedoop

WORKDIR /kubedoop
