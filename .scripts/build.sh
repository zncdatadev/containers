#!/bin/bash

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
      --cache-from string     Use an image as build cache
      --cache-to string       Push the built image to the registry
"
  local tag
  local dockerfile=""
  local platform=""
  local push=false
  local cache_from=""
  local cache_to=""
  local progress=""
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
      --cache-from )
        shift
        cache_from=$1
        ;;
      --cache-to )
        shift
        cache_to=$1
        ;;
      --progress )
        shift
        progress=$1
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

  builder "$tag" "$dockerfile" "$platform" "$push" "$cache_from" "$cache_to" "$progress" "$build_args" "$context"
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
      --progress string           Set the progress output type [auto, plain, tty], default is auto
      --cache-dir string          Set the cache directory
"

  local context
  local dockerfile=""
  local push=false
  local platform=""
  local progress=""
  local cache_dir=""
  local product_version=""

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
      --progress )
        shift
        progress=$1
        ;;
      --cache-dir )
        shift
        cache_dir=$1
        ;;
      --product-version )
        shift
        product_version=$1
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

  local result=$(build_product_with_metadata "$context")

  for item in $(echo $result | jq -c '.[]'); do
    local tag=$(echo $item | jq -r '.tag')

    local build_args=()
    if echo $item | jq -e '.build_args?' > /dev/null; then
      build_args=$(echo $item | jq -r '.build_args[]' | tr '\n' ' ')
    fi

    builder "$tag" "$dockerfile" "$platform" "$push" "" "" "$progress" "$build_args" "$context"
  done

}

function main () {
  local usage="
Usage: build.sh COMMAND [OPTIONS] PATH

Build image

Commands:
  image                       Build the image
  product                     Build the product image

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
    * )
      echo "$usage"
      exit 1
      ;;
  esac
}

main "$@"
