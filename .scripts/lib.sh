#!/bin/bash

DEFAULT_PLATFORM="linux/amd64,linux/arm64"
REGISTRY=${REGISTRY:-"quay.io/zncdatadev"}
PLATFORM_VERSION=${PLATFORM_VERSION:-"0.0.0-dev"}
PLATFORM_NAME=${PLATFORM_NAME:-"kubedoop"}
PLATFORM_TAG="$PLATFORM_NAME$PLATFORM_VERSION"

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
#   $1: required  product path
#   $2: optional  product version, if not set, return all versions
# Returns:
#   JSON: product metadata
#    {
#      "tag": "quay.io/zncdatadev/airflow:1.10.12-kubedoop5.3.1",
#      "build_args": ["PRODUCT_VERSION=1.10.12", "BASE_IMAGE=quay.io/zncdatadev/python:3.8.5-kubedoop0.0.0-dev"],
#    }
function build_product_with_metadata () {
  local product_path=$1
  local filter_version=$2

  local metadata_file="$product_path/metadata.json"
  local product_name=$(jq -r '.name' $metadata_file)  

  local result=()

  for property in $(jq -c '.properties[]' $metadata_file); do
    
    local product_version=$(echo $property | jq -r '.version')
    local build_args=("PRODUCT_VERSION=$product_version")
    local tag="$REGISTRY/$product_name:$product_version-$PLATFORM_TAG"

    # Create a json object with tag
    local property_json=$(jq -n --arg tag "$tag" '{tag: $tag}')

    local base_image=""
    if echo $property | jq -e '.upstream?' > /dev/null; then
      local upstream_name=$(echo $property | jq -r '.upstream.name')
      local upstream_version=$(echo $property | jq -r '.upstream.version')
      base_image="BASE_IMAGE=$REGISTRY/$upstream_name:$upstream_version-$PLATFORM_TAG"
      build_args+=($base_image)
    fi

    if echo $property | jq -e '.dependencies?' >> /dev/null; then
      local deps=$(echo $property | jq -r '.dependencies | to_entries | map("\(.key | ascii_upcase)_VERSION=\(.value)") | join(" ")')
      build_args+=($deps)
    fi
    local build_args_json=$(printf '%s\n' "${build_args[@]}" | jq -R . | jq -s .)
    property_json=$(echo "$property_json" | jq --argjson build_args "$build_args_json" '. + {build_args: $build_args}')

    if [ -n "$filter_version" ] && [ "$filter_version" == "$product_version" ]; then
      result=($property_json)
      break
    fi

    result+=($property_json)
  done

  echo "${result[@]}" | jq -s '.' 
}
