REGISTRY ?= quay.io/zncdatadev
PLATFORM_VERSION ?= 0.0.0-dev

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

PLATFORMS ?= linux/arm64,linux/amd64

LOCAL_BIN = ./bin

##@ install

.PHONY: jq
JQ = $(LOCAL_BIN)/jq
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
kubedoop-base-build: jq ## Build kubedoop-base image
	.scripts/build.sh product kubedoop-base

.PHONY:
kubedoop-base-buildx: jq ## Build kubedoop-base image with buildx
	.scripts/build.sh product kubedoop-base --push

.PHONY:
vector-build: ## Build Vector image
	.scripts/build.sh product vector	

.PHONY:
vector-buildx: jq ## Build Vector image with buildx
	.scripts/build.sh product vector --push

##@ develop environment

.PHONY:
java-base-build: jq ## Build Java base image
	.scripts/build.sh product java-base

.PHONY:
java-devel-build: jq ## Build Java development image
	.scripts/build.sh product java-devel

##@ product

.PHONY:
zookeeper-build: jq ## Build Zookeeper image
	.scripts/build.sh product zookeeper

.PHONY:
zookeeper-buildx: jq ## Build Zookeeper image with buildx
	.scripts/build.sh product zookeeper --push

.PHONY:
hadoop-build: jq ## Build Hadoop image
	.scripts/build.sh product hadoop

.PHONY:
hadoop-buildx: jq ## Build Hadoop image with buildx
	.scripts/build.sh product hadoop --push

.PHONY:
hive-build: jq ## Build Hive image
	.scripts/build.sh product hive

.PHONY:
hive-buildx: jq ## Build Hive image with buildx
	.scripts/build.sh product hive --push

.PHONY:
kafka-build: jq ## Build Kafka image
	.scripts/build.sh product kafka

.PHONY:
kafka-buildx: jq ## Build Kafka image with buildx
	.scripts/build.sh product kafka --push

.PHONY:
hbase-build: jq ## Build HBase image
	.scripts/build.sh product hbase

.PHONY:
hbase-buildx: jq ## Build HBase image with buildx
	.scripts/build.sh product hbase --push

.PHONY:
spark-build: jq ## Build Spark image
	.scripts/build.sh product spark

.PHONY:
spark-buildx: jq ## Build Spark image with buildx
	.scripts/build.sh product spark --push
