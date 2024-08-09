#!/bin/bash

set -e

. .scripts/lib.sh

# if CI_SCRIPT_DEBUG is set, then enable debug mode
if [ -n "$CI_SCRIPT_DEBUG" ]; then
  set -x
fi

DEFAULT_PLATFORM="linux/amd64,linux/arm64"
REGISTRY=${REGISTRY:-"quay.io/zncdatadev"}
STACK_VERSION=${STACK_VERSION:-"0.0.0-dev"}


# Build docker image
# Arguments:
#   $1: tag
#   $2: dockerfile
#   $3: platform
#   $4: push
#   $5: cache-from
#   $6: cache-to
#   $7: progress
#   $8: build-arg list
#   $9: context
# Returns:
function builder () {
  local tag=$1
  local dockerfile=$2
  local platform=$3
  local push=$4
  local cache_from=$5
  local cache_to=$6
  local progress=$7
  local build_args=$8
  local context=$9

  local container_tool="docker"
  local build_cmd="build --tag $tag"

  # use buildx if push is true
  if [ "$push" = true ]; then
    container_tool="$container_tool buildx"
    platform="${platform:-$DEFAULT_PLATFORM}"

    build_cmd="$build_cmd --push --platform $platform"

    # cache-from && cache-to exist
    if [ -n "$cache_from" ] && [ -n "$cache_to" ]; then
      build_cmd="$build_cmd --cache-from type=local,src=$cache_from --cache-to type=local,dest=$cache_to"
    elif [ -n "$DOCKER_CACHE_DIR" ]; then
      build_cmd="$build_cmd --cache-from type=local,src=$DOCKER_CACHE_DIR --cache-to type=local,dest=$DOCKER_CACHE_DIR"
    fi
  fi

  if [ -n "$dockerfile" ]; then
    build_cmd="$build_cmd --file $dockerfile"
  fi

  if [ -n "$build_args" ]; then
    for arg in $build_args; do
      build_cmd="$build_cmd --build-arg $arg"
      echo "Build arg: $arg"
    done
  fi
  

  build_cmd="$container_tool $build_cmd $context"

  echo "Building image..."

  eval $build_cmd

  # if push is false, show docker images to debug
  if [ "$push" = false ]; then
    echo "Show docker images"
    docker images
    echo "Inspect image"
    docker inspect $tag
  fi

}

# Parse product metadata.json in product path
# Arguments:
#   $1: product path
# Returns:
#   JSON: product metadata
#    {
#      "tag": "quay.io/zncdatadev/airflow:1.10.12",
#      "build_args": ["PRODUCT_VERSION=1.10.12", "BASE_IMAGE=quay.io/zncdatadev/python:3.8.5-stack0.0.0-dev"],
#    }
function build_product_with_metadata () {
  local product_path=$1
  local metadata_file="$product_path/metadata.json"
  local product_name=$(jq -r '.name' $metadata_file)  

  local result=()

  for property in $(jq -c '.properties[]' $metadata_file); do
    
    local product_version=$(echo $property | jq -r '.version')
    local build_args=("PRODUCT_VERSION=$product_version")
    local tag="$REGISTRY/$product_name:$product_version-stack$STACK_VERSION"

    # Create a json object with tag
    local property_json=$(jq -n --arg tag "$tag" '{tag: $tag}')

    local base_image=""
    if echo $property | jq -e '.upstream?' > /dev/null; then
      local upstream_name=$(echo $property | jq -r '.upstream.name')
      local upstream_version=$(echo $property | jq -r '.upstream.version')
      local upstream_stack=$(echo $property | jq -r '.upstream.stack')
      base_image="BASE_IMAGE=$REGISTRY/$upstream_name:$upstream_version-stack$upstream_stack"
      build_args+=($base_image)
    fi

    if echo $property | jq -e '.dependencies?' >> /dev/null; then
      local deps=$(echo $property | jq -r '.dependencies | to_entries | map("\(.key | ascii_upcase)_VERSION=\(.value)") | join(" ")')
      build_args+=($deps)
    fi
    local build_args_json=$(printf '%s\n' "${build_args[@]}" | jq -R . | jq -s .)
    property_json=$(echo "$property_json" | jq --argjson build_args "$build_args_json" '. + {build_args: $build_args}')
    result+=($property_json)
  done

  echo "${result[@]}" | jq -s '.' 
}


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
  -h, --help                  Show this message
  -f, --file string           Set the Dockerfile path, default is Dockerfile
      --push                  Push the built image to the registry
      --platform string       Set the platform for the image, default is linux/amd64,linux/arm64.
      --progress string       Set the progress output type [auto, plain, tty], default is auto
      --cache-dir string      Set the cache directory
"

  local context
  local dockerfile=""
  local push=false
  local platform=""
  local progress=""
  local cache_dir=""

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
