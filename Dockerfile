ARG BASE_IMAGE=ubuntu:jammy
ARG DEBIAN_DEPS="coreutils"
ARG INSTALL_CMD="https://raw.githubusercontent.com/LCAS/docker-fpm/main/test.yaml"
ARG PACKAGE_NAME="foo"
ARG VERSION="0.0.1"
ARG MAINTAINER="L-CAS <mhanheide@lincoln.ac.uk>"


FROM $BASE_IMAGE as prepare

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
        wget \
	&& gem install fpm \
	&& mkdir /deb-build-fpm /docker-fpm
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&    chmod +x /usr/bin/yq


FROM prepare as setup
ARG BASE_IMAGE
ARG DEBIAN_DEPS
ARG INSTALL_CMD
ARG PACKAGE_NAME
ARG VERSION
ARG MAINTAINER

ENV DEBIAN_FRONTEND noninteractive
ENV BASE_IMAGE=${BASE_IMAGE}
ENV DEBIAN_DEPS=${DEBIAN_DEPS}
ENV INSTALL_CMD=${INSTALL_CMD}
ENV PACKAGE_NAME=${PACKAGE_NAME}
ENV VERSION=${VERSION}
ENV MAINTAINER=${MAINTAINER}
SHELL ["/bin/bash", "-c"]

ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" /.skipcache
RUN if echo ${INSTALL_CMD} | grep -q '^http'; then \
      echo "URL provided, running in YAML mode"; \
      wget -O /deb-build-fpm/config.yaml "${INSTALL_CMD}"; \
        yq eval '.install' /deb-build-fpm/config.yaml > /deb-build-fpm/install.sh; \
        export INSTALL_CMD="bash /deb-build-fpm/install.sh"; \
        export DEBIAN_DEPS=$(yq eval '.dependencies[]' /deb-build-fpm/config.yaml | tr "\n" " "); \
        export PACKAGE_NAME=$(yq eval '.package' /deb-build-fpm/config.yaml); \
        export VERSION=$(yq eval '.version' /deb-build-fpm/config.yaml); \
        export MAINTAINER=$(yq eval '.maintainer' /deb-build-fpm/config.yaml); \
        export BASE_IMAGE=$(yq eval '.baseimage' /deb-build-fpm/config.yaml); \
    else \
      echo "Running in shell mode, taking commands as verbatim"; \
    fi;\
    echo -n "" > /deb-build-fpm/setup.bash; \
    echo "BASE_IMAGE=${BASE_IMAGE}" >> /deb-build-fpm/setup.bash; \
    echo "DEBIAN_DEPS='${DEBIAN_DEPS}'" >> /deb-build-fpm/setup.bash; \
    echo "INSTALL_CMD='${INSTALL_CMD}'" >> /deb-build-fpm/setup.bash; \
    echo "PACKAGE_NAME='${PACKAGE_NAME}'" >> /deb-build-fpm/setup.bash; \
    echo "VERSION='${VERSION}'" >> /deb-build-fpm/setup.bash; \
    echo "MAINTAINER='${MAINTAINER}'" >> /deb-build-fpm/setup.bash; \
    echo "BASE_IMAGE='${BASE_IMAGE}'" >> /deb-build-fpm/setup.bash;

RUN cat /deb-build-fpm/setup.bash

FROM setup as install

RUN set -x; \
    source /deb-build-fpm/setup.bash; \
	apt-get update \
    && apt-get install -y --no-install-recommends \
        ${DEBIAN_DEPS}

#WORKDIR /deb-build-fpm/
RUN find `find / -maxdepth 1 -mindepth 1 -type d | grep -v "/proc" | grep -v  "/boot"| grep -v  "/sys" | grep -v  "/dev"` -type f -print0 | xargs -0 md5sum > /deb-build-fpm/A.txt

RUN source /deb-build-fpm/setup.bash; bash -x -e -c "${INSTALL_CMD}"

RUN find `find / -maxdepth 1 -mindepth 1 -type d | grep -v "/proc" | grep -v  "/boot"| grep -v  "/sys" | grep -v  "/dev"` -type f -print0 | xargs -0 md5sum > /deb-build-fpm/B.txt
RUN IFS='\n' diff /deb-build-fpm/A.txt /deb-build-fpm/B.txt | grep -v '/deb-build-fpm/A.txt$' | grep -v '/deb-build-fpm/B.txt$' | grep '^> ' | cut -f4 -d" " > /deb-build-fpm/changes.txt
RUN source /deb-build-fpm/setup.bash; tar -czf /deb-build-fpm/${PACKAGE_NAME}.tgz --files-from - < /deb-build-fpm/changes.txt

FROM setup as build

#RUN gem install fpm
COPY --from=install /deb-build-fpm /deb-build-fpm
WORKDIR /deb-build-fpm
RUN source /deb-build-fpm/setup.bash; echo -n "" > /deb-build-fpm/deps.txt; for dep in ${DEBIAN_DEPS}; do echo " -d $dep" >> /deb-build-fpm/deps.txt; done
RUN source /deb-build-fpm/setup.bash; echo fpm -s tar -m "${MAINTAINER}" -v "${VERSION}" `cat /deb-build-fpm/deps.txt` -t deb   "/deb-build-fpm/${PACKAGE_NAME}.tgz"
RUN source /deb-build-fpm/setup.bash; fpm -s tar -m "${MAINTAINER}" -n "${PACKAGE_NAME}" -f -v "${VERSION}" `cat /deb-build-fpm/deps.txt` -t deb   "/deb-build-fpm/${PACKAGE_NAME}.tgz"



FROM ${BASE_IMAGE} as test
COPY --from=build /deb-build-fpm /deb-build-fpm
RUN apt-get update && apt-get install -y /deb-build-fpm/*.deb

FROM test as final
COPY --from=build /deb-build-fpm /deb-build-fpm
CMD ls /deb-build-fpm; cp -v /deb-build-fpm/* /output

#ENTRYPOINT /docker-fpm/scan-dirs.sh

