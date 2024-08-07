REGISTRY ?= quay.io/zncdatadev
STACK_VERSION ?= 0.0.0-dev
BASE_STACK_VERSION ?= 0.0.0-dev

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

PLATFORMS ?= linux/arm64,linux/amd64

##@ install

.PHONY: jq
JQ = ./bin/jq
jq: ## Download jq locally if necessary.
ifeq (,$(wildcard $(JQ)))
ifeq (,$(shell which jq 2>/dev/null))
    @{ \
		set -e ;\
		mkdir -p $(dir $(JQ)) ;\
		OS=$(shell uname -s | tr '[:upper:]' '[:lower:]') && \
		ARCH=$(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/') && \
		if [ "$${OS}" = "darwin" ]; then OS="macos"; fi && \
		curl -sSLo $(JQ) https://github.com/jqlang/jq/releases/latest/download/jq-$${OS}-$${ARCH} ;\
		chmod +x $(JQ) ;\
    }
else
JQ = $(shell which jq)
endif
endif

##@ infra

.PHONY:
kubedata-base-build: ## Build kubedata-base image
	set -ex ;\
	pushd kubedata-base ;\
	PRODUCT_NAME=$$($(JQ) -r '.name' metadata.json) ;\
	for property in $$($(JQ) -c '.properties[]' metadata.json); do \
		PRODUCT_VERSION=$$(echo $$property | $(JQ) -r '.version') ;\
		$(CONTAINER_TOOL) build \
			-t $(REGISTRY)/$${PRODUCT_NAME}:$${PRODUCT_VERSION}-stack$(BASE_STACK_VERSION) \
			-f Dockerfile . ;\
	done
	popd

.PHONY:
kubedata-base-buildx: jq ## Build kubedata-base image with buildx
	set -ex ;\
	pushd kubedata-base ;\
	PRODUCT_NAME=$$($(JQ) -r '.name' metadata.json) ;\
	for property in $$($(JQ) -c '.properties[]' metadata.json); do \
		PRODUCT_VERSION=$$(echo $$property | $(JQ) -r '.version') ;\
		$(CONTAINER_TOOL) buildx build \
			--push \
			--platform $(PLATFORMS) \
			-t $(REGISTRY)/$${PRODUCT_NAME}:$${PRODUCT_VERSION}-stack$(BASE_STACK_VERSION) \
			-f Dockerfile . ;\
	done


.PHONY:
vector-build: ## Build Vector image
	set -ex ;\
	pushd vector ;\
	PRODUCT_NAME=$$($(JQ) -r '.name' metadata.json) ;\
	for property in $$($(JQ) -c '.properties[]' metadata.json); do \
		PRODUCT_VERSION=$$(echo $$property | $(JQ) -r '.version') ;\
		UPSTREAM_NAME=$$(echo $$property | $(JQ) -r '.upstream.name') ;\
		UPSTREAM_VERSION=$$(echo $$property | $(JQ) -r '.upstream.version') ;\
		$(CONTAINER_TOOL) build \
			--build-arg BASE_IMAGE=$(REGISTRY)/$${UPSTREAM_NAME}:$${UPSTREAM_VERSION}-stack$(BASE_STACK_VERSION) \
			--build-arg PRODUCT_VERSION=$${PRODUCT_VERSION} \
			-t $(REGISTRY)/$${PRODUCT_NAME}:$${PRODUCT_VERSION}-stack$(BASE_STACK_VERSION) \
			-f Dockerfile . ;\
	done

##@ develop environment

.PHONY:
java-base-build: ## Build Java base image
	set -ex ;\
	pushd java-base ;\
	PRODUCT_NAME=$$($(JQ) -r '.name' metadata.json) ;\
	for property in $$($(JQ) -c '.properties[]' metadata.json) ; do \
		PRODUCT_VERSION=$$(echo $$property | $(JQ) -r '.version') ;\
		UPSTREAM_NAME=$$(echo $$property | $(JQ) -r '.upstream.name') ;\
		UPSTREAM_VERSION=$$(echo $$property | $(JQ) -r '.upstream.version') ;\
		$(CONTAINER_TOOL) build \
			--build-arg BASE_IMAGE=$(REGISTRY)/$${UPSTREAM_NAME}:$${UPSTREAM_VERSION}-stack$(BASE_STACK_VERSION) \
			--build-arg PRODUCT_VERSION=$${PRODUCT_VERSION} \
			-t $(REGISTRY)/$${PRODUCT_NAME}:$${PRODUCT_VERSION}-stack$(BASE_STACK_VERSION) \
			-f Dockerfile . ;\
	done

.PHONY:
java-devel-build: ## Build Java development image
	set -ex ;\
	pushd java-devel ;\
	PRODUCT_NAME=$$($(JQ) -r '.name' metadata.json) ;\
	for property in $$($(JQ) -c '.properties[]' metadata.json) ; do \
		PRODUCT_VERSION=$$(echo $$property | $(JQ) -r '.version') ;\
		UPSTREAM_NAME=$$(echo $$property | $(JQ) -r '.upstream.name') ;\
		UPSTREAM_VERSION=$$(echo $$property | $(JQ) -r '.upstream.version') ;\
		DEPENDENCIES=$$(echo $$property | $(JQ) -r '.dependencies | to_entries | map("--build-arg \(.key | ascii_upcase)_VERSION=\(.value)") | join(" ")') ;\
		$(CONTAINER_TOOL) build \
			--build-arg BASE_IMAGE=$(REGISTRY)/$${UPSTREAM_NAME}:$${UPSTREAM_VERSION}-stack$(BASE_STACK_VERSION) \
			--build-arg PRODUCT_VERSION=$${PRODUCT_VERSION} \
			$${DEPENDENCIES} \
			-t $(REGISTRY)/$${PRODUCT_NAME}:$${PRODUCT_VERSION}-stack$(STACK_VERSION) \
			-f Dockerfile . ;\
	done

##@ product
