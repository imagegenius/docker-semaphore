# build semaphore
FROM golang:1.19-alpine3.16 as builder

# set version
ARG SEMAPHORE_VERSION

RUN set -e && \
  echo "**** install build packages ****" && \
  apk add --no-cache \
    curl \
    gcc \
    git \
    jq \
    libc-dev \
    nodejs \
    npm && \
  echo "**** download semaphore ****" && \
  if [ -z ${SEMAPHORE_VERSION} ]; then \
    SEMAPHORE_VERSION=$(curl -sL https://api.github.com/repos/ansible-semaphore/semaphore/releases/latest | \
      jq -r '.tag_name'); \
  fi && \
  git clone https://github.com/ansible-semaphore/semaphore.git /go/src/github.com/ansible-semaphore/semaphore && \
  cd /go/src/github.com/ansible-semaphore/semaphore && \
  git checkout ${SEMAPHORE_VERSION} && \
  (cd $(go env GOPATH) && curl -sL https://taskfile.dev/install.sh | sh) && \
  task deps && \
  task compile && \
  task build:local GOOS=linux GOARCH=amd64 && \
  mkdir /out && \
  mv ./deployment/docker/common/semaphore-wrapper /out && \
  mv ./bin/semaphore /out

# runtime
FROM ghcr.io/imagegenius/baseimage-alpine:3.18

# set version label
ARG BUILD_DATE
ARG VERSION
ARG SEMAPHORE_VERSION
LABEL build_version="ImageGenius Version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="hydazz"

# environment settings
ENV SEMAPHORE_TMP_PATH="/tmp/semaphore" \
  SEMAPHORE_CONFIG_PATH="/config" \
  SEMAPHORE_DB_PATH="/config"

COPY --from=builder /out/* /usr/local/bin/

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    ansible \
    git \
    mysql-client \
    nano \
    openssh-client-default \
    py3-aiohttp \
    py3-pip \
    rsync \
    sshpass && \
  pip3 install --no-cache \
    passlib && \
  echo "**** cleanup ****" && \
  for cleanfiles in *.pyc *.pyo; do \
    find /usr/lib/python3.* -iname "${cleanfiles}" -delete; \
  done && \
  rm -rf \
    /tmp/*

# set home
ENV HOME=/config

# copy local files
COPY root/ /

# ports and volumes
EXPOSE 3000
VOLUME /config
