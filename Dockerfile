# build semaphore
FROM golang:1.20-alpine3.18 as builder

# set version
ARG SEMAPHORE_VERSION

RUN set -e && \
  echo "**** install build packages ****" && \
  apk add --no-cache \
    curl \
    g++ \
    gcc \
    git \
    jq \
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
  (cd $(go env GOPATH) && go install github.com/go-task/task/v3/cmd/task@latest) && \
  git config --global --add safe.directory /go/src/github.com/ansible-semaphore/semaphore && \
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
  SEMAPHORE_DB_PATH="/config" \
  ANSIBLE_HOST_KEY_CHECKING=False

COPY --from=builder /out/* /usr/local/bin/

RUN \
  echo "**** install build packages ****" && \
  apk add --no-cache --virtual=build-dependencies \
    build-base \
    libffi-dev \
    openssl-dev \
    python3-dev && \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    curl-dev \
    g++ \
    gcc \
    git \
    mysql-client \
    nodejs \
    npm \
    openssh-client-default \
    openssl \
    py-openssl \
    py3-pip \
    python3 \
    rsync \
    sshpass && \
  pip3 install -U --no-cache \
    cffi \
    pip && \
  pip3 install --no-cache \
    ansible \
    passlib && \
  echo "**** cleanup ****" && \
  for cleanfiles in *.pyc *.pyo; do \
    find /usr/lib/python3.* -iname "${cleanfiles}" -delete; \
  done && \
  apk del --purge \
    build-dependencies && \
  rm -rf \
    /tmp/*

# set home
ENV HOME=/config

# copy local files
COPY root/ /

# ports and volumes
EXPOSE 3000
VOLUME /config
