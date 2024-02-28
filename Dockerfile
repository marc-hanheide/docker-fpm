# Define build arguments
ARG BASE_IMAGE=ubuntu:jammy
ARG DEBIAN_DEPS="coreutils"
ARG INSTALL_CMD="https://raw.githubusercontent.com/LCAS/docker-fpm/main/test.yaml"
ARG PACKAGE_NAME="foo"
ARG VERSION="0.0.1"
ARG MAINTAINER="L-CAS <mhanheide@lincoln.ac.uk>"

# Stage 1: Prepare the environment
FROM $BASE_IMAGE as prepare
RUN echo "::group::prepare"

# Install necessary dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    set -x \
	&& apt-get update && apt-get install -y --no-install-recommends \
    curl  lsb-release curl software-properties-common apt-transport-https ca-certificates gnupg2

# Add ROS and LCAS repositories
RUN sh -c 'echo "deb http://packages.ros.org/ros2/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list' && \
    curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | apt-key add -

RUN sh -c 'echo "deb https://lcas.lincoln.ac.uk/apt/lcas $(lsb_release -sc) lcas" > /etc/apt/sources.list.d/lcas-latest.list' && \
    sh -c 'echo "deb https://lcas.lincoln.ac.uk/apt/staging $(lsb_release -sc) lcas" > /etc/apt/sources.list.d/lcas-staging.list' && \
    curl -s https://lcas.lincoln.ac.uk/apt/repo_signing.gpg | apt-key add -

# Install additional dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    set -x \
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

# Download yq binary
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&    chmod +x /usr/bin/yq
RUN echo "::endgroup::"

# Stage 2: Setup the environment
FROM prepare as setup
ARG BASE_IMAGE
ARG DEBIAN_DEPS
ARG INSTALL_CMD
ARG PRE_INSTALL_CMD
ARG PACKAGE_NAME
ARG VERSION
ARG MAINTAINER
ARG DESCRIPTION

# Set environment variables
ENV DEBIAN_FRONTEND noninteractive
ENV BASE_IMAGE=${BASE_IMAGE}
ENV DEBIAN_DEPS=${DEBIAN_DEPS}
ENV INSTALL_CMD=${INSTALL_CMD}
ENV PACKAGE_NAME=${PACKAGE_NAME}
ENV VERSION=${VERSION}
ENV MAINTAINER=${MAINTAINER}
ENV PRE_INSTALL_CMD=${PRE_INSTALL_CMD}
ENV DESCRIPTION=${DESCRIPTION}
SHELL ["/bin/bash", "-c"]

# Add skipcache file to prevent caching
ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" /.skipcache

RUN echo "::group::setup"

RUN mkdir /tmp/configs

# copy all yaml files into the container so that `file//` works
COPY *.yaml /tmp/configs

# Check if INSTALL_CMD is a URL, if yes, run in YAML mode
RUN set -xe; if echo ${INSTALL_CMD} | grep -q '^http\|^file:'; then \
        echo "URL provided, running in YAML mode"; \
        if echo ${INSTALL_CMD} | grep -q '^http'; then \
            wget -O /deb-build-fpm/config.yaml "${INSTALL_CMD}"; \
        else \
            filename="/tmp/configs/$(echo ${INSTALL_CMD} | sed 's@^file://@@')"; \
            cp -v "${filename}" /deb-build-fpm/config.yaml; \
        fi; \
        yq -e '.install' /deb-build-fpm/config.yaml > /deb-build-fpm/install.sh; \
        yq -e eval '.preinstall' /deb-build-fpm/config.yaml > /deb-build-fpm/pre-install.sh || echo "true" > /deb-build-fpm/pre-install.sh ; \
        export INSTALL_CMD="bash /deb-build-fpm/install.sh"; \
        export PRE_INSTALL_CMD="bash /deb-build-fpm/pre-install.sh"; \
        export DEBIAN_DEPS=$(yq -e eval '.dependencies[]' /deb-build-fpm/config.yaml | tr "\n" " "); \
        export PACKAGE_NAME=$(yq -e eval '.package' /deb-build-fpm/config.yaml); \
        export DESCRIPTION=$(yq -e eval ".description // \"The ${PACKAGE_NAME} package\"" /deb-build-fpm/config.yaml); \
        export VERSION=$(yq -e eval '.version' /deb-build-fpm/config.yaml); \
        export MAINTAINER=$(yq eval '.maintainer // "no maintainer <noreply@nowhere.org>"' /deb-build-fpm/config.yaml); \
        export BASE_IMAGE=$(yq eval '.baseimage // "ubuntu:jammy"' /deb-build-fpm/config.yaml); \
    else \
        echo "Running in shell mode, taking commands as verbatim"; \
    fi; \
    # Create setup.bash file with environment variables
    echo -n "" > /deb-build-fpm/setup.bash; \
        echo "BASE_IMAGE=${BASE_IMAGE}" >> /deb-build-fpm/setup.bash; \
        echo "DEBIAN_DEPS='${DEBIAN_DEPS}'" >> /deb-build-fpm/setup.bash; \
        echo "INSTALL_CMD='${INSTALL_CMD}'" >> /deb-build-fpm/setup.bash; \
        echo "PACKAGE_NAME='${PACKAGE_NAME}'" >> /deb-build-fpm/setup.bash; \
        echo "VERSION='${VERSION}'" >> /deb-build-fpm/setup.bash; \
        echo "MAINTAINER='${MAINTAINER}'" >> /deb-build-fpm/setup.bash; \
        echo "PRE_INSTALL_CMD='${PRE_INSTALL_CMD}'" >> /deb-build-fpm/setup.bash; \
        echo "BASE_IMAGE='${BASE_IMAGE}'" >> /deb-build-fpm/setup.bash; \
        echo "DESCRIPTION='${DESCRIPTION}'" >> /deb-build-fpm/setup.bash;

RUN cat /deb-build-fpm/setup.bash
RUN echo "::endgroup::"

# Stage 3: Install dependencies
FROM prepare as install

COPY --from=setup /deb-build-fpm /
RUN ls -l /deb-build-fpm /

RUN echo "::group::install dependencies"
RUN --mount=type=cache,target=/var/cache/apt \
    set -x; \
    source /deb-build-fpm/setup.bash; \
	apt-get update \
    && apt-get install -y --no-install-recommends \
        ${DEBIAN_DEPS}
RUN echo "::endgroup::"

RUN echo "::group::pre-install command"
RUN mkdir /tmp/build-package
WORKDIR /tmp/build-package
RUN source /deb-build-fpm/setup.bash; echo "run ${PRE_INSTALL_CMD}"
RUN source /deb-build-fpm/setup.bash; bash -x -e -c "${PRE_INSTALL_CMD}"
RUN echo "::endgroup::"

# Calculate checksum of files before running the command
RUN find `find / -maxdepth 1 -mindepth 1 -type d | grep -v "/proc" | grep -v  "/boot"| grep -v  "/sys" | grep -v  "/dev" | grep -v  "/root" | grep -v  "/deb-build-fpm" | grep -v  "/tmp"` -type f -print0 | xargs -0 md5sum > /deb-build-fpm/A.txt

RUN echo "::group::run command"
RUN source /deb-build-fpm/setup.bash; echo "run ${INSTALL_CMD}"
RUN source /deb-build-fpm/setup.bash; bash -x -e -c "${INSTALL_CMD}"
RUN echo "::endgroup::"

RUN rm -rf /tmp/build-package

# Calculate checksum of files after running the command
RUN find `find / -maxdepth 1 -mindepth 1 -type d | grep -v "/proc" | grep -v  "/boot"| grep -v  "/sys" | grep -v  "/dev" | grep -v  "/root" | grep -v  "/deb-build-fpm" | grep -v  "/tmp"` -type f -print0 | xargs -0 md5sum > /deb-build-fpm/B.txt

# Find the changes made by the command and save them to changes.txt
RUN IFS='\n' diff /deb-build-fpm/A.txt /deb-build-fpm/B.txt | grep -v '/deb-build-fpm/A.txt$' | grep -v '/deb-build-fpm/B.txt$' | grep -v '/var/cache' | grep -v '/var/log' | grep -v '/etc/ld.so.cache$' || grep '^> ' | cut -f4 -d" " > /deb-build-fpm/changes.txt

# Create a tarball of the changes
RUN source /deb-build-fpm/setup.bash; tar -czf /deb-build-fpm/${PACKAGE_NAME}.tgz --files-from - < /deb-build-fpm/changes.txt

# Stage 4: Build the final image
FROM setup as build

# Copy the deb-build-fpm directory from the install stage
COPY --from=install /deb-build-fpm /

WORKDIR /deb-build-fpm
COPY ./ldconfig.sh /deb-build-fpm/ldconfig.sh

# Create deps.txt file with dependency information
RUN source /deb-build-fpm/setup.bash; echo -n "" > /deb-build-fpm/deps.txt; for dep in ${DEBIAN_DEPS}; do echo " -d $dep" >> /deb-build-fpm/deps.txt; done

RUN echo "::group::build deb package"
#RUN source /deb-build-fpm/setup.bash; echo fpm -s tar -m "${MAINTAINER}" -v "${VERSION}" `cat /deb-build-fpm/deps.txt` -t deb   "/deb-build-fpm/${PACKAGE_NAME}.tgz"
RUN source /deb-build-fpm/setup.bash; fpm -s tar --description "${DESCRIPTION}" --after-remove ./ldconfig.sh --after-install ./ldconfig.sh -m "${MAINTAINER}" -n "${PACKAGE_NAME}" -f -v "${VERSION}" `cat /deb-build-fpm/deps.txt` -t deb   "/deb-build-fpm/${PACKAGE_NAME}.tgz"
RUN echo "::endgroup::"

# Stage 5: Test the installation
FROM ${BASE_IMAGE} as test
COPY --from=build /deb-build-fpm /deb-build-fpm
ENV DEBIAN_FRONTEND noninteractive
RUN echo "::group::test install"
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y /deb-build-fpm/*.deb
RUN echo "::endgroup::"

# Stage 6: Create the final image
FROM test as final
COPY --from=build /deb-build-fpm /deb-build-fpm
CMD echo "::group::show all outputs"; ls /deb-build-fpm; cp -v /deb-build-fpm/* /output; echo "::endgroup::"

#ENTRYPOINT /docker-fpm/scan-dirs.sh
