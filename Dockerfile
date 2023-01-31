ARG SYNAPSE_VERSION=1.76
ARG HARDENED_MALLOC_VERSION=11
ARG UID=991
ARG GID=991

### Build Hardened Malloc
FROM alpine:latest as build-malloc

ARG HARDENED_MALLOC_VERSION
ARG CONFIG_NATIVE=false
ARG VARIANT=default

RUN apk --no-cache add build-base git gnupg && cd /tmp \
 && wget -q https://github.com/thestinger.gpg && gpg --import thestinger.gpg \
 && git clone --depth 1 --branch ${HARDENED_MALLOC_VERSION} https://github.com/GrapheneOS/hardened_malloc \
 && cd hardened_malloc && git verify-tag $(git describe --tags) \
 && make CONFIG_NATIVE=${CONFIG_NATIVE} VARIANT=${VARIANT}

### Nginx & Redis
FROM alpine:latest as deps_base

RUN apk --no-cache add nginx redis

### Redis Base
FROM redis:6-alpine AS redis_base

### Build Synapse
FROM python:alpine as builder

ARG SYNAPSE_VERSION

RUN apk -U upgrade \
 && apk add -t build-deps \
        build-base \
        libffi-dev \
        libjpeg-turbo-dev \
        libressl-dev \
        libxslt-dev \
        linux-headers \
        postgresql-dev \
        rustup \
        zlib-dev \
        git \
 && rustup-init -y && source $HOME/.cargo/env \
 && pip install --upgrade pip \
 && pip install --prefix="/install" --no-warn-script-location \
   -e "git+https://git.anonymousland.org/anonymousland/synapse-product#egg=matrix-synapse[all]==${SYNAPSE_VERSION}"

### Build Production

FROM python:alpine

ARG UID
ARG GID

RUN apk -U upgrade \
 && apk add -t run-deps \
        libffi \
        libgcc \
        libjpeg-turbo \
        libressl \
        libstdc++ \
        libxslt \
        libpq \
        zlib \
        tzdata \
        xmlsec \
        git \
        curl \
        icu-libs \
 && adduser -g ${GID} -u ${UID} --disabled-password --gecos "" synapse \
 && rm -rf /var/cache/apk/*
 
RUN set -x ; \
  addgroup -g 82 -S www-data ; \
  adduser -u 82 -D -S -G www-data www-data && exit 0 ; exit 1

RUN pip install --upgrade pip \
 && pip install -e "git+https://github.com/matrix-org/mjolnir.git#egg=mjolnir&subdirectory=synapse_antispam"

RUN --mount=type=cache,target=/root/.cache/pip \
        pip install supervisor~=4.2

RUN pip install Jinja2

RUN mkdir /var/log/nginx /var/lib/nginx

COPY --from=deps_base /usr/sbin/nginx /usr/sbin
COPY --from=deps_base /usr/share/nginx /usr/share/nginx
COPY --from=deps_base /usr/lib/nginx /usr/lib/nginx
COPY --from=deps_base /etc/nginx /etc/nginx

RUN chown www-data /var/lib/nginx
RUN mkdir /var/lib/nginx/logs/
RUN chown 991:www-data /var/lib/nginx/logs/
RUN ln -sf /dev/stdout /var/log/nginx/access.log
RUN ln -sf /dev/stderr /var/log/nginx/error.log

COPY --from=build-malloc /tmp/hardened_malloc/out/libhardened_malloc.so /usr/local/lib/
COPY --from=builder /install /usr/local
COPY --chown=synapse:synapse ./rootfs /
COPY --from=redis_base /usr/local/bin/redis-server /usr/local/bin

COPY ./rootfs/start.py /start.py
COPY ./rootfs/conf-workers/* /conf/
COPY ./rootfs/configure_workers_and_start.py /configure_workers_and_start.py
COPY ./prefix-log /usr/local/bin/

RUN chown -R synapse:synapse /conf/
RUN chown -R synapse:www-data /etc/nginx
RUN chown synapse:synapse /usr/local/lib/libhardened_malloc.so

RUN mkdir -p /etc/supervisor/conf.d
RUN mkdir -p /etc/nginx/conf.d
RUN chown -R synapse:www-data /etc/nginx

RUN mkdir -p /health/
RUN chown -R synapse:synapse /health/

RUN chown -R synapse:synapse /etc/supervisor

RUN chmod +x /usr/local/bin/prefix-log

RUN chmod 755 /start.py

RUN chown synapse:synapse /

ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"

USER synapse

VOLUME /data

EXPOSE 8008/tcp

CMD ["python3", "/configure_workers_and_start.py"]

HEALTHCHECK --start-period=5s --interval=15s --timeout=5s \
    CMD /bin/sh /healthcheck.sh