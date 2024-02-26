#!/bin/bash

# add command line flag processing

baseimage="ubuntu:jammy"

while getopts ":v:p:c:d:u:h" opt; do
    case $opt in
        v) version=$OPTARG;;
        p) package=$OPTARG;;
        c) command=$OPTARG;;
        b) baseimage=$OPTARG;;
        d) deps=$OPTARG;;
        h) echo "Usage: ./make-deb.sh -v <version> -p <package> -c <command> -d <deps>"
           echo "Options:"
           echo "  -v <version>   Set the version (e.g. 0.0.1)"
           echo "  -p <package>   Set the package name"
           echo "  -c <command>   Set the command to run"
           echo "  -b <image_tag> Docker baseimage to use (default: ubuntu:jammy)"
           echo "  -d <deps>      declare the ubuntu package dependencies"
           exit;;
        \?) echo "Invalid option -$OPTARG" >&2;;
    esac
done

# if $command or $version or $package is empty, then print usage and exit
if [ -z "$command" ] || [ -z "$version" ] || [ -z "$package" ] || [ -z "$deps" ]; then
    echo "Usage:     `basename $0` -v <version> -p <package> -c <command> -d <deps>"
    echo "  Example: `basename $0` -v 0.0.1 -p camdriver -c \"cmake . && make\" -d \"libusb-1.0-0-dev,libudev-dev\""
    exit
fi  


# Usage example:
# ./make-deb.sh -v 0.0.1 -p mypackage -c mycommand
mkdir -p output

image_name="fpm_build_debian_${package}_${version}_`date +%s`"

docker build \
    --build-arg VERSION="$version" \
    --build-arg DEBIAN_DEPS="$deps" \
    --build-arg INSTALL_CMD="$command" \
    --build-arg PACKAGE_NAME="$package" \
    --build-arg BASE_IMAGE="$baseimage" \
    --progress=plain -t $image_name . && \
  docker run -v `pwd`/output:/output --rm $image_name && \
  docker rmi $image_name

