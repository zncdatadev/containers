# syntax=docker/dockerfile:1

ARG VECTOR_VERSION

## stage: builder
FROM quay.io/zncdatadev/vector:${VECTOR_VERSION}-kubedoop0.0.0-dev AS builder

ARG PRODUCT_VERSION
ARG PYTHON_VERSION

RUN <<EOF
    microdnf update
    microdnf install \
        cyrus-sasl-devel \
        gcc \
        gcc-c++ \
        jq \
        libffi-devel \
        libpq-devel \
        make \
        openldap-devel \
        openssl-devel \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-devel \
        python${PYTHON_VERSION}-pip \
        python${PYTHON_VERSION}-setuptools \
        python${PYTHON_VERSION}-wheel \
        
    microdnf clean all
EOF

WORKDIR /kubedoop


RUN <<EOF
    set -ex
    python${PYTHON_VERSION} -m venv app
    source app/bin/activate
    pip install --upgrade --no-cache-dir pip setuptools wheel

    AIRFLOW_EXTRAS=async,amazon,celery,cncf.kubernetes,docker,dask,elasticsearch,ftp,grpc,hashicorp,http,ldap,google,google_auth,microsoft.azure,odbc,pandas,postgres,redis,sendgrid,sftp,slack,ssh,statsd,virtualenv,trino
    CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${PRODUCT_VERSION}/constraints-${PYTHON_VERSION}.txt"
    pip install --no-cache-dir apache-airflow[${AIRFLOW_EXTRAS}]==${PRODUCT_VERSION} --constraint ${CONSTRAINT_URL}

    pip install --no-cache-dir s3fs Flask_OIDC==2.2.0 Flask-OpenID==1.3.1

EOF

# smoke test
RUN /kubedoop/app/bin/airflow version | grep -q ${PRODUCT_VERSION}

## stage: statsd exporter
FROM quay.io/zncdatadev/kubedoop-base:1.0.0-kubedoop0.0.0-dev AS statsd-exporter-builder

ARG STATSD_EXPORTER_VERSION

WORKDIR /build

RUN <<EOF
    microdnf update
    microdnf install \
        golang \
        gzip \
        tar \
        xz
        
    microdnf clean all
    
EOF

# download and build statsd-exporter

RUN <<EOF
    set -ex
    mkdir -p /build/statsd-exporter-src
    pushd /build/statsd-exporter-src
    curl -sSfL \
        https://github.com/prometheus/statsd_exporter/archive/refs/tags/v${STATSD_EXPORTER_VERSION}.tar.gz \
        | tar xzf - --strip-components=1

    go build -o /kubedoop/bin/statsd-exporter
    popd
EOF

# smoke test
RUN /kubedoop/bin/statsd-exporter --version

# stage: git-sync-builder
FROM quay.io/zncdatadev/go-devel:1.22.9-kubedoop0.0.0-dev AS git-sync-builder

ARG GIT_SYNC_VERSION

WORKDIR /build

RUN <<EOF
    set -ex
    export VERSION=${GIT_SYNC_VERSION}
    git clone --branch v${GIT_SYNC_VERSION} --depth 1 https://github.com/kubernetes/git-sync.git
    cd git-sync

    export OS=$(go env GOOS)
    export ARCH=$(go env GOARCH)
    export GOBIN=$(pwd)/bin

    ./build/build.sh

    mkdir -p /kubedoop/bin
    mv bin/git-sync /kubedoop/bin
EOF

# smoke test
RUN /kubedoop/bin/git-sync --version


# stage: final
FROM quay.io/zncdatadev/vector:${VECTOR_VERSION}-kubedoop0.0.0-dev

ARG PRODUCT_VERSION
ARG PYTHON_VERSION


RUN <<EOF
    set -ex
    microdnf update
    microdnf install \
        cyrus-sasl \
        libpq \
        make \
        openldap \
        openldap-clients \
        openssh-clients \
        openssl \
        openssl-libs \
        openssl-pkcs11 \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip \
        socat \
        unixODBC \

    microdnf clean all
EOF

COPY --from=builder --chown=kubedoop:kubedoop /kubedoop /kubedoop
COPY --from=statsd-exporter-builder --chown=kubedoop:kubedoop /kubedoop/bin/statsd-exporter /kubedoop/bin/statsd-exporter
COPY --from=git-sync-builder --chown=kubedoop:kubedoop /kubedoop/bin/git-sync /kubedoop/bin/git-sync
COPY kubedoop/bin/entrypoint.sh /kubedoop/bin/entrypoint.sh

ENV VIRTUAL_ENV=/kubedoop/app
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}" \
    AIRFLOW_HOME=/kubedoop/airflow

WORKDIR /kubedoop

USER kubedoop

ENTRYPOINT [ "/kubedoop/bin/entrypoint.sh" ]
