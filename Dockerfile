ARG BASE_IMAGE=ubuntu:jammy
FROM $BASE_IMAGE

ENV DEBIAN_FRONTEND noninteractive

RUN set -x \
	&& apt-get update && apt-get install -y --no-install-recommends \
		ruby \
		ruby-dev \
        coreutils \
		gcc \
		make \
		ca-certificates \
		libffi-dev \
		ruby-ffi \
	&& gem install fpm \
	&& mkdir /src /docker-fpm

COPY . /docker-fpm
WORKDIR /src/

#ENTRYPOINT /docker-fpm/scan-dirs.sh

