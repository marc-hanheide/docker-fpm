ARG BASE_IMAGE=ubuntu:jammy
ARG DEBIAN_DEPS="coreutils"
ARG INSTALL_CMD="touch /usr/local/foo2"
ARG PACKAGE_NAME="foo"
ARG VERSION="0.0.1"
ARG MAINTAINER="L-CAS <mhanheide@lincoln.ac.uk>"


FROM $BASE_IMAGE as prepare

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
	&& mkdir /deb-build-fpm /docker-fpm

FROM prepare as install
ARG INSTALL_CMD
ARG PACKAGE_NAME

RUN set -x \
	&& apt-get update && apt-get install -y --no-install-recommends \
        ${DEBIAN_DEPS}

#WORKDIR /deb-build-fpm/
RUN find `find / -maxdepth 1 -mindepth 1 -type d | grep -v "/proc" | grep -v  "/boot"| grep -v  "/sys" | grep -v  "/dev"` -type f -print0 | xargs -0 md5sum > /deb-build-fpm/A.txt
RUN ${INSTALL_CMD}
RUN find `find / -maxdepth 1 -mindepth 1 -type d | grep -v "/proc" | grep -v  "/boot"| grep -v  "/sys" | grep -v  "/dev"` -type f -print0 | xargs -0 md5sum > /deb-build-fpm/B.txt
RUN IFS='\n' diff /deb-build-fpm/A.txt /deb-build-fpm/B.txt | grep -v '/deb-build-fpm/A.txt$' | grep -v '/deb-build-fpm/B.txt$' | grep '^> ' | cut -f4 -d" " > /deb-build-fpm/changes.txt
RUN tar -czf /deb-build-fpm/${PACKAGE_NAME}.tgz --files-from - < /deb-build-fpm/changes.txt

FROM prepare as build
ARG PACKAGE_NAME
ARG VERSION
ARG DEBIAN_DEPS
ARG MAINTAINER
RUN gem install fpm
COPY . /docker-fpm
COPY --from=install /deb-build-fpm /deb-build-fpm
WORKDIR /deb-build-fpm
RUN echo -n "" > /deb-build-fpm/deps.txt; for dep in ${DEBIAN_DEPS}; do echo " -d $dep" >> /deb-build-fpm/deps.txt; done
RUN echo fpm -s tar -m "${MAINTAINER}" -v "${VERSION}" `cat /deb-build-fpm/deps.txt` -t deb   "/deb-build-fpm/${PACKAGE_NAME}.tgz"
RUN fpm -s tar -m "${MAINTAINER}" -v "${VERSION}" `cat /deb-build-fpm/deps.txt` -t deb   "/deb-build-fpm/${PACKAGE_NAME}.tgz"



FROM ${BASE_IMAGE} as test
COPY --from=build /deb-build-fpm /deb-build-fpm
RUN apt-get update && apt-get install -y /deb-build-fpm/*.deb

FROM ${BASE_IMAGE} as final
COPY --from=build /deb-build-fpm /deb-build-fpm
CMD ls /deb-build-fpm; cp -v /deb-build-fpm/* /output

#ENTRYPOINT /docker-fpm/scan-dirs.sh

