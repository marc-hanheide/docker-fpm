# Build (Ubuntu) Deb package from install commands

This little tool uses [FPM](https://fpm.readthedocs.io/) and [Docker](https://www.docker.com/) to generate simple Debian packages from a set of commands that install the required software. It simple monitors which files have changed as a result of a set of bash commands and puts these into a `.deb` package.

## Installation

* Requirements: 
  * Docker
  * bash
* clone this repository

## Use with a config file

This mode is intended to be used with a publicly available config file such as [`https://raw.githubusercontent.com/LCAS/docker-fpm/main/test.yaml`](https://raw.githubusercontent.com/LCAS/docker-fpm/main/test.yaml). The config file is in YAML format and has these required fields:
* `install`: The actual set of commands to be run installing whatever you need. The files that are installed from these commands are the content of the generated package
* `package`: The name of the package to be generated, must follow Debian rules for package names
* `version`: The semanti version string of the package, e.g. `0.0.1`
* `maintainer`: The maintainer of the package, usually a name and email address like `Joe Doe <jdoe@gmail.com>`
* `dependencies`: An array of Ubuntu dependencies that are installed prior to running the `install` commands and also are declared as the dependencies of the generated package
* here an example
    ```
    install: |
    echo "Hello, world!"
    echo "This is a test."
    echo "This is only a test."
    echo "This is a test of the emergency broadcast system."
    echo "If this had been an actual emergency, you would have been instructed where to tune in your area for news and official information."
    echo "This concludes this test of the emergency broadcast system."
    echo "Goodbye."
    package: foo
    maintainer: "Marc Hanheide <marc@hanheide.net>"
    version: 0.0.2
    dependencies: 
    - coreutils
    - bash
    ```

Run the tool with such a config file URL:
```
./make-deb.sh -c "https://raw.githubusercontent.com/LCAS/docker-fpm/main/test.yaml" 
```

Optionally, you can set the base image to be used, to build a package for a different distribution: `./make-deb.sh -c "https://raw.githubusercontent.com/LCAS/docker-fpm/main/test.yaml -b ubuntu:23.10"` 


## Using command line flags only (without config file)

If there is no config file and to do a quich run with out, use command line flags only, e.g.

```
./make-deb.sh -v 0.0.1 -c "touch /etc/FOO" -p foo_new -d "nano coreutils" -b ubuntu:jammy
```

Usage:
```
Usage: make-deb.sh -c <URL to YAML config file> or make-deb.sh -v <version> -p <package> -c <command> -d <deps>
Options:
  -v <version>   Set the version (e.g. 0.0.1), not needed with URL config
  -p <package>   Set the package name, not needed with URL config
  -c <command>   Set the command to run OR the URL to a YAML config file
  -b <image_tag> Docker baseimage to use (default: ubuntu:jammy), not needed with URL config
  -d <deps>      declare the ubuntu package dependencies, not needed with URL config
```

