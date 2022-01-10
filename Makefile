SHELL := /bin/bash
.DEFAULT_GOAL = help

# See article on "Deferred Simple Variable Expansion" in make - http://make.mad-scientist.net/deferred-simple-variable-expansion/

# GOPROXY - 
# When using JFrog Artifactory and the JFrog CLI, use the Go repository URL as configured for the JFrog CLI.
# If you want to use the default / globally configured GOPROXY - simply comment the export statement below.
# (getting first line and first "column" in case jfrog cli returns more than just the GOPROXY value... (it happens...) )
export GOPROXY := $(eval GOPROXY := $(shell jfrog rt go env GOPROXY 2>&1 | grep -o "http.*" | head -1 | cut -d' ' -f1))$(GOPROXY)

# Eagerly evaluates the GOOS & GOARCH variables
export GOOS := $(eval GOOS := $(shell go env GOOS 2>&1))$(GOOS)
export GOARCH := $(eval GOARCH := $(shell go env GOARCH 2>&1))$(GOARCH)

# GOCMD -
# Set the Go commad to use, defaults to `go`, but can be set otherwise when running make, e.g. to use Go via the JFrog CLI:
#   GOCMD="jfrog rt go" make foo
export GOCMD ?= go

# BINARY_BASE_NAME -
# The binary base name is used below in several places. Change it here once.
BINARY_BASE_NAME := myapp

# APP_MAIN_SRC_FILE -
# The source file where the main finction of the application is.
# By default it is based on the binary base name, but it can be changed.
APP_MAIN_SRC_FILE := ./${BINARY_BASE_NAME}.go

# APP_NAME -
# A descriptive name for the application, shown in the 'help' goal
APP_NAME := "My Application"

# APP_IMAGE_TAG_DEV -
# The image tag name to use when building and running the docker image for the application.
# Note - the same image is also used in the docker-compose.yml file, if modified make sure they are aligned.
APP_IMAGE_TAG_DEV := "${BINARY_BASE_NAME}:dev"

# SRC_FILES -
# Collect all the source files - used by make to detect changes (for incremental builds).
# Adjust the `find` command below based on your specific needs
SRC_FILES := $(shell find internal/*)

# ----------------------------------------------------- TARGETS -----------------------------------------------------
# Notes:
# - Make supports incremental build by depending on the existence and modification timestamps of files on the file system.
#   Some artifacts are not really simple files, like docker images. To support incremental build for those artifacts as well, 
#   we are using marker files. For each such artifact an `out/*.marker` file is created when the artifact is created and then
#   used.

out:
	mkdir out

out/${BINARY_BASE_NAME}-darwin-amd64: out go.mod ${APP_MAIN_SRC_FILE} ${INTERNAL_SRC_FILES}
	GOOS=darwin GOARCH=amd64 ${GOCMD} build -o out/${BINARY_BASE_NAME}-darwin-amd64 ${APP_MAIN_SRC_FILE}

out/${BINARY_BASE_NAME}-linux-amd64: out go.mod ${APP_MAIN_SRC_FILE} ${INTERNAL_SRC_FILES}
	# https://medium.com/@diogok/on-golang-static-binaries-cross-compiling-and-plugins-1aed33499671
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 ${GOCMD} build -o out/${BINARY_BASE_NAME}-linux-amd64 -ldflags '-w -extldflags "-static"' ${APP_MAIN_SRC_FILE}

##  binary         build the service binary for the current OS and architecture
.PHONY: binary
binary: out/${BINARY_BASE_NAME}-${GOOS}-${GOARCH}

out/go-junit-report.marker: out
	${GOCMD} install github.com/jstemmer/go-junit-report@latest
	@echo ${shell date +%s} > out/go-junit-report.marker

##  test           run unit tests
.PHONY: test
test: out out/go-junit-report.marker
	${GOCMD} test ./... -v 2>&1 | tee /dev/stderr | go-junit-report > out/test-report.xml

##  check-fmt      run code formatting check
.PHONY: check-fmt
check-fmt:
	@echo "check-fmt"
	@test -z "$(shell gofmt -l -d $$(find . -name '*.go') | tee /dev/stderr)"

##  check-vet      run Go vet static code analysis check
.PHONY: check-vet
check-vet:
	@echo "check-vet"
	${GOCMD} vet ./...

##  check          run static code checks
.PHONY: check
check: check-fmt check-vet

##  run            run the service locally
.PHONY: run
run:
	${GOCMD} run ${APP_MAIN_SRC_FILE}

##  clean          clean previous build output
.PHONY: clean
clean:
	rm -rf out

out/docker-image.marker: out out/${BINARY_BASE_NAME}-linux-amd64 Dockerfile
	docker build -t ${APP_IMAGE_TAG_DEV} .
	@echo ${shell date +%s} > out/docker-image.marker

##  docker-image   build the docker image
.PHONY: docker-image
docker-image: out/docker-image.marker

##  docker-run     run the docker image with default configuration
.PHONY: docker-run
docker-run: out/docker-image.marker
	docker-compose --file docker-compose.yml up --detach

##  docker-stop    stop the docker container that was started by docker-run
.PHONY: docker-stop
docker-stop:
	docker-compose --file docker-compose.yml down

##  help           show this help
.PHONY: help
help: Makefile
	@printf "\
	Usage: make <goal>... [<variable>...] \n\
	\n\
	Makefile of ${APP_NAME} \n\
	\n\
	Goals:\n"
	@sed -n 's/^## //p' $<
	@printf "\n"
	@printf "\
	Variables:\n"
	@sed -n 's/^#### //p' $<
	@printf "\n"