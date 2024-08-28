#!/bin/bash

CONTAINER_TOOL_PROVIDER=${CONTAINER_TOOL_PROVIDER:-"podman"}
SIGNER_TOOL_PROVIDER=${SIGNER_TOOL_PROVIDER:-"cosign"}

set -e

. .scripts/lib.sh

# if CI_SCRIPT_DEBUG is set, then enable debug mode
if [ -n "$CI_SCRIPT_DEBUG" ]; then
  set -x
fi


function build_image () {
  local usage="
Usage: command <Arguments> [OPTIONS] PATH

Build the image

Arguments:
  -t, --tag string            Set the tag for the image

Options:
  -h, --help                  Show this message
  -d, --debug                 Build in debug mode
  -f, --file string           Set the Dockerfile path, default is Dockerfile
      --push                  Push the built image to the registry
      --build-arg sring       Pass build arguments to the image, can be used multiple times
      --platform string       Set the platform for the image, default is linux/amd64,linux/arm64.
"
  local tag
  local dockerfile=""
  local platform=""
  local push=false
  local build_args=()

  while [ "$1" != "" ]; do
    case $1 in
      -t | --tag )
        shift
        tag=$1
        ;;
      -f | --file )
        shift
        dockerfile=$1
        ;;
      --platform )
        shift
        platform=$1
        ;;
      --push )
        push=true
        ;;
      --build-arg )
        shift
        build_args+=($1)
        ;;
      --context )
        shift
        context=$1
        ;;
      -h | --help )
        echo "$usage"
        exit 0
        ;;
      * )
        if [ -n "$context" ]; then
          echo "Invalid argument: $1"
          exit 1
        fi
        context=$1
        ;;
    esac
    shift
  done

  if [ -z "$tag" ]; then
    echo "Tag is required"
    exit 1
  fi

  builder "$CONTAINER_TOOL_PROVIDER" "$tag" "$dockerfile" "$platform" $push "$build_args" "$context"
}


function build_product () {
  local usage="
Usage: command [OPTIONS] PATH

Build the product image

Options:
  -h, --help                      Show this message
  -f, --file string               Set the Dockerfile path, default is Dockerfile
      --product-version string    Set the product version
      --push                      Push the built image to the registry
      --platform string           Set the platform for the image, default is linux/amd64,linux/arm64.
      --sign string               Sign the image, currently only support cosign
"

  local context
  local dockerfile=""
  local push=false
  local platform=""
  local product_version=""
  local sign="$SIGNER_TOOL_PROVIDER"

  while [ "$1" != "" ]; do
    case $1 in
      -f | --file )
        shift
        dockerfile=$1
        ;;
      --push )
        push=true
        ;;
      --platform )
        shift
        platform=$1
        ;;
      --product-version )
        shift
        product_version=$1
        ;;
      --sign )
        shift
        sign=$1
        ;;
      -h | --help )
        echo "$usage"
        exit 0
        ;;
      * )
        # if context already set, then exit
        if [ -n "$context" ]; then
          echo "Invalid argument: $1"
          exit 1
        fi
        context=$1
        ;;
    esac
    shift
  done

  if [ -z "$context" ]; then
    echo "Context is required"
    exit 1
  fi

  local result=$(get_product_metadata "$context" "$product_version")

  for item in $(echo $result | jq -c '.[]'); do
    local tag=$(echo $item | jq -r '.tag')

    local build_args=()
    if echo $item | jq -e '.build_args?' > /dev/null; then
      build_args=$(echo $item | jq -r '.build_args[]' | tr '\n' ' ')
    fi

    builder "$CONTAINER_TOOL_PROVIDER" "$tag" "$dockerfile" "$platform" $push "$build_args" "$context" "$sign"
  done

}

function main () {
  local usage="
Usage: build.sh COMMAND [OPTIONS]

Build image

Commands:
  image                       Build the image
  product                     Build the product image

Options:
  -h, --help                  Show this message

"
  local command=$1
  shift

  case $command in
    image )
      build_image "$@"
      ;;
    product )
      build_product "$@"
      ;;
    -h | --help )
      echo "$usage"
      exit 0
      ;;
    * )
      echo "$usage"
      exit 1
      ;;
  esac
}

function system_requirements () {
  if ! command -v jq > /dev/null; then
    echo "jq is required"
    exit 1
  fi

  if ! command -v $CONTAINER_TOOL_PROVIDER > /dev/null; then
    echo "$CONTAINER_TOOL_PROVIDER is required"
    exit 1
  fi

  if ! command -v $SIGNER_TOOL_PROVIDER > /dev/null; then
    echo "$SIGNER_TOOL_PROVIDER is required"
    exit 1
  fi
}


system_requirements
main "$@"
