FROM alpine:3.10 AS builder
MAINTAINER Thornton Phillis (Th0rn0@lanops.co.uk)

# ENV - Config

ENV UUID 1000
ENV GUID 1000
ENV NGINX_VERSION 1.16.1
ENV NJS_VERSION   0.3.8
ENV PKG_RELEASE   1
ENV PHP_VERSION 7.3
ENV SUPERVISOR_LOG_ROOT /var/log/supervisor
ENV NGINX_DOCUMENT_ROOT /web/html

# Install Dependencies

RUN apk add --no-cache --virtual .build-deps \
	gcc \
	g++ \
	make

RUN apk add --no-cache \
	tzdata \
	curl \
	bash \
	libc-dev \
	openssl-dev \
	pcre-dev \
	zlib-dev \
	linux-headers \
	gnupg \
	libxslt-dev \
	gd-dev \
	imagemagick \
	geoip-dev

RUN apk add --no-cache supervisor \
	&& mkdir -p $SUPERVISOR_LOG_ROOT

# Install Nginx

RUN set -x \
# create nginx user/group first, to be consistent throughout docker variants
    && addgroup -g 101 -S nginx \
    && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    && apkArch="$(cat /etc/apk/arch)" \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${PKG_RELEASE} \
    " \
    && case "$apkArch" in \
        x86_64) \
# arches officially built by upstream
            set -x \
            && KEY_SHA512="e7fa8303923d9b95db37a77ad46c68fd4755ff935d0a534d26eba83de193c76166c68bfe7f65471bf8881004ef4aa6df3e34689c305662750c0172fca5d8552a *stdin" \
            && apk add --no-cache --virtual .cert-deps \
                openssl \
            && wget -O /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
            && if [ "$(openssl rsa -pubin -in /tmp/nginx_signing.rsa.pub -text -noout | openssl sha512 -r)" = "$KEY_SHA512" ]; then \
                echo "key verification succeeded!"; \
                mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/; \
            else \
                echo "key verification failed!"; \
                exit 1; \
            fi \
            && apk del .cert-deps \
            && apk add -X "https://nginx.org/packages/alpine/v$(egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release)/main" --no-cache $nginxPackages \
            ;; \
        *) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from the published packaging sources
            set -x \
            && tempDir="$(mktemp -d)" \
            && chown nobody:nobody $tempDir \
            && apk add --no-cache --virtual .build-deps \
                gcc \
                libc-dev \
                make \
                openssl-dev \
                pcre-dev \
                zlib-dev \
                linux-headers \
                libxslt-dev \
                gd-dev \
                geoip-dev \
                perl-dev \
                libedit-dev \
                mercurial \
                bash \
                alpine-sdk \
                findutils \
            && su nobody -s /bin/sh -c " \
                export HOME=${tempDir} \
                && cd ${tempDir} \
                && hg clone https://hg.nginx.org/pkg-oss \
                && cd pkg-oss \
                && hg up -r 450 \
                && cd alpine \
                && make all \
                && apk index -o ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz ${tempDir}/packages/alpine/${apkArch}/*.apk \
                && abuild-sign -k ${tempDir}/.abuild/abuild-key.rsa ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz \
                " \
            && cp ${tempDir}/.abuild/abuild-key.rsa.pub /etc/apk/keys/ \
            && apk del .build-deps \
            && apk add -X ${tempDir}/packages/alpine/ --no-cache $nginxPackages \
            ;; \
    esac \
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    && if [ -n "$tempDir" ]; then rm -rf "$tempDir"; fi \
    && if [ -n "/etc/apk/keys/abuild-key.rsa.pub" ]; then rm -f /etc/apk/keys/abuild-key.rsa.pub; fi \
    && if [ -n "/etc/apk/keys/nginx_signing.rsa.pub" ]; then rm -f /etc/apk/keys/nginx_signing.rsa.pub; fi \
# Bring in gettext so we can get `envsubst`, then throw
# the rest away. To do this, we need to install `gettext`
# then move `envsubst` out of the way so `gettext` can
# be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
        scanelf --needed --nobanner /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
# Bring in tzdata so users could set the timezones through the environment
# variables
    && apk add --no-cache tzdata \
# forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log
# Install PHP

RUN apk add --update --no-cache \
        php7-session>=${PHP_VERSION} \
        php7-mcrypt>=${PHP_VERSION} \
        php7-openssl>=${PHP_VERSION} \
        php7-json>=${PHP_VERSION} \
        php7-dom>=${PHP_VERSION} \
        php7-zip>=${PHP_VERSION} \
        php7-bcmath>=${PHP_VERSION} \
        php7-gd>=${PHP_VERSION} \
        php7-odbc>=${PHP_VERSION} \
        php7-gettext>=${PHP_VERSION} \
        php7-xmlreader>=${PHP_VERSION} \
        php7-xmlwriter>=${PHP_VERSION} \
        php7-xmlrpc>=${PHP_VERSION} \
        php7-xml>=${PHP_VERSION} \
        php7-simplexml>=${PHP_VERSION} \
        php7-bz2>=${PHP_VERSION} \
        php7-iconv>=${PHP_VERSION} \
        php7-curl>=${PHP_VERSION} \
        php7-ctype>=${PHP_VERSION} \
        php7-pcntl>=${PHP_VERSION} \
        php7-posix>=${PHP_VERSION} \
        php7-phar>=${PHP_VERSION} \
        php7-opcache>=${PHP_VERSION} \
        php7-mbstring>=${PHP_VERSION} \
        php7-fileinfo>=${PHP_VERSION} \
        php7-tokenizer>=${PHP_VERSION} \
        php7-opcache>=${PHP_VERSION} \
        php7-pdo>=${PHP_VERSION} \
        php7-mysqli>=${PHP_VERSION} \
        php7-pdo_mysql>=${PHP_VERSION} \
        php7-pear>=${PHP_VERSION} \
        php7-fpm>=${PHP_VERSION} \
        php7-mbstring>=${PHP_VERSION} \
        php7-imagick>=${PHP_VERSION} \
    	php7-dev>=${PHP_VERSION}

RUN rm -f /var/cache/apk/* \
    && mkdir -p /opt/utils

# Clean Up

RUN apk del .build-deps
