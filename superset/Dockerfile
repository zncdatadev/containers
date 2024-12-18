# syntax=docker/dockerfile:1
# check=error=true


## stage: builder
FROM zncdatadev/image/vector AS superset-builder

ARG PRODUCT_VERSION
ARG PYTHON_VERSION
ARG AUTHLIB_VERSION

RUN <<EOF
    microdnf update
    microdnf install \
        cyrus-sasl-devel \
        gcc \
        gcc-c++ \
        make \
        openldap-devel \
        openssl-devel \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-devel \
        python${PYTHON_VERSION}-pip \
        python${PYTHON_VERSION}-setuptools \
        python${PYTHON_VERSION}-wheel \
        libffi-devel \
        libpq-devel

    microdnf clean all
    rm -rf /var/cache/yum
EOF

WORKDIR /kubedoop

RUN <<EOF
    set -ex
    python${PYTHON_VERSION} -m venv app
    source app/bin/activate
    pip install --upgrade --no-cache-dir pip setuptools wheel
    pip install --no-cache-dir \
        apache-superset==${PRODUCT_VERSION} \
        psycopg2-binary \
        pydruid \
        python-json-logger \
        python-ldap \
        statsd \
        trino[sqlalchemy] \
        tzdata

    # if AUTHLIB_VERSION is set, install the specified version
    if [ -n "${AUTHLIB_VERSION}" ]; then
        pip install --no-cache-dir authlib==${AUTHLIB_VERSION}
    fi

    # smoke test
    SUPERSET_SECRET_KEY=$(openssl rand -hex 32) FLASK_APP="superset.app:create_app()" /kubedoop/app/bin/superset version
EOF


## stage: statsd exporter
FROM zncdatadev/image/vector AS statsd-exporter-builder

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
    rm -rf /var/cache/yum
EOF

# download and build statsd-exporter

RUN <<EOF
    mkdir -p /build/statsd-exporter-src
    pushd /build/statsd-exporter-src
    curl -sSfL \
        https://github.com/prometheus/statsd_exporter/archive/refs/tags/v${STATSD_EXPORTER_VERSION}.tar.gz \
        | tar xzf - --strip-components=1

    go build -o /kubedoop/bin/statsd-exporter
    popd

    # smoke test
    /kubedoop/bin/statsd-exporter --version

    # cleanup source
    rm -rf /build/statsd-exporter-src

    # cleanup cache
    go clean -modcache
    rm -rf /root/.cache/go-build
EOF


## stage: final
FROM zncdatadev/image/vector

ARG PRODUCT_VERSION
ARG PYTHON_VERSION

RUN <<EOF
    microdnf update
    microdnf install \
        cyrus-sasl \
        libpq \
        make \
        openssl \
        openssl-libs \
        openldap \
        openldap-clients \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip

    microdnf clean all
    rm -rf /var/cache/yum
EOF

WORKDIR /kubedoop

COPY --from=statsd-exporter-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/
COPY --from=superset-builder --chown=kubedoop:kubedoop /kubedoop/app /kubedoop/app

COPY kubedoop/bin/entrypoint.sh /kubedoop/bin/entrypoint.sh

ENV VIRTUAL_ENV=/kubedoop/app
ENV SUPERSET_ENV=production \
    FLASK_APP="superset.app:create_app()" \
    PYTHONPATH="/kubedoop/app/pythonpath:$PYTHONPATH" \
    PATH="${VIRTUAL_ENV}/bin:$PATH" \
    SUPERSET_PORT=8088

EXPOSE ${SUPERSET_PORT}

WORKDIR /kubedoop/app

USER kubedoop

CMD [ "/kubedoop/bin/entrypoint.sh" ]
