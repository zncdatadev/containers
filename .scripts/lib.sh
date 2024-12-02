#!/bin/bash

set -ex

DEFAULT_PLATFORM="linux/amd64,linux/arm64"
REGISTRY=${REGISTRY:-"quay.io/zncdatadev"}
PLATFORM_VERSION=${PLATFORM_VERSION:-"0.0.0-dev"}
PLATFORM_NAME=${PLATFORM_NAME:-"kubedoop"}
PLATFORM_TAG="$PLATFORM_NAME$PLATFORM_VERSION"

CI_DEBUG=${CI_DEBUG:-false}


# Build image with docker
function docker_builder() {
  echo "EROR: TODO: Implement docker_builder" >&2
}


# Build image with nerdctl
function nerdctl_builder () {
  echo "EROR: TODO: Implement nerdctl_builder" >&2
}


# buildah or podman backend adaptor
# Arguments:
#   $1: str   tag
#   $2: str   dockerfile
#   $3: str   platform
#   $4: bool  push
#   $5: array build-args array, (k1=v1 k2=v2)
#   $6: str   context
#   $7: bool   sign
#   $8: bool  is_podman
# Returns:
#   None
function buildah_backend_adaptor () {
  local tag=$1
  local dockerfile=$2
  local platform=$3
  local push=$4
  local build_args=$5
  local context=$6
  local sign=$7
  # if 'is_podman' set and true, use podman
  local is_podman=${8:-false}

  local container_tool="buildah"
  local platform_length=$(echo $platform | tr ',' '\n' | wc -l)

  if [ $is_podman = true ]; then
    container_tool="podman"
  fi

  local buildah_args=("build")

  # if 'push' is true, and platform less then 2, use default platform
  if [ $push = true ] && [ $platform_length -lt 2 ]; then
    platform=$DEFAULT_PLATFORM
    platform_length=$(echo $platform | tr ',' '\n' | wc -l)
  fi

  # if 'platform' set and more then one, use --manifest
  # else use --tag
  if [ $platform_length -gt 1 ]; then
    buildah_args+=("--manifest=${tag}")
    buildah_args+=("--platform=${platform}")
    buildah_args+=("--jobs=4")
  else
    buildah_args+=("--tag=${tag}")
  fi


  if [ -n "$dockerfile" ]; then
    buildah_args+=("--file=${dockerfile}")
  fi

  if [ -n "$build_args" ]; then
    for arg in $build_args; do
      buildah_args+=("--build-arg=${arg}")
    done
  fi

  buildah_args+=("${context}")

  # build image
  echo "INFO: Building image: ${buildah_args[*]}" >&2
  $container_tool ${buildah_args[@]}

  # if CI_DEBUG is true, list images
  if [ $CI_DEBUG = true ]; then
    $container_tool images
  fi

  if [ $platform_length -gt 1 ]; then
    echo "INFO: Inspecting manifest: $tag" >&2
    $container_tool manifest inspect $tag
  elif [ $push = true ]; then
    echo "INFO: Inspecting image: $tag" >&2
    $container_tool inspect $tag
  fi

  local digest_file=$(echo $tag | tr '/:' '-')_digest.txt

  # if 'push' set and true, push image
  if [ $push = true ]; then
    # if 'platform' seted, push manifest else push image
    if [ $platform_length -gt 1 ]; then
      echo "INFO: Pushing manifest: $tag" >&2
      $container_tool manifest push --digestfile $digest_file --all $tag
    else
      echo "INFO: Pushing image: $tag" >&2
      $container_tool push --digestfile $digest_file $tag
    fi

    local image_digest=$(cat $digest_file)

    # if 'sign' is set and image_digest is not empty, sign image
    if [ $sign = true ] && [ -n "$image_digest" ]; then
      local digest_tag=$(echo "$tag" | sed "s/:[^:]*$/@$image_digest/")
      echo "INFO: Signing image: $digest_tag" >&2
      image_signer "$digest_tag" true "cosign"
    fi
  fi

}


# Build image with buildah
# Arguments:
#   $1: str   tag
#   $2: str   dockerfile
#   $3: str   platform
#   $4: bool  push
#   $5: array build-args array, (k1=v1 k2=v2)
#   $6: str   context
#   $7: bool   sign
# Returns:
#   None
function buildah_builder () {
  local tag=$1
  local dockerfile=$2
  local platform=$3
  local push=$4
  local build_args=$5
  local context=$6
  local sign=$7

  buildah_backend_adaptor "$tag" "$dockerfile" "$platform" $push "$build_args" "$context" $sign false
}


# Build image with podman
# Arguments:
#   $1: str   tag
#   $2: str   dockerfile
#   $3: str   platform
#   $4: bool  push
#   $5: array build-args array, (k1=v1 k2=v2)
#   $6: str   context
#   $7: bool   sign
# Returns:
#   None
function podman_builder () {
  local tag=$1
  local dockerfile=$2
  local platform=$3
  local push=$4
  local build_args=$5
  local context=$6
  local sign=$7

  buildah_backend_adaptor "$tag" "$dockerfile" "$platform" $push "$build_args" "$context" $sign true
}


# Factory method to return builder tool
# Arguments:
#   $1: str   builder tool name,vaild docker, buildah, podman, nerdctl
# Returns:
#   $1: str   builder implementation function name
function builder_factory () {
  local builder_tool=$1
  case $builder_tool in
    "docker" | "buildah" | "podman" | "nerdctl")
      local builder_impl="${builder_tool}_builder"
      echo "INFO: Builder tool: $builder_impl" >&2
      echo $builder_impl
      ;;
    *)
      echo "EROR: Unsupported builder tool: $builder_tool"
      exit 1
      ;;
  esac
}


# Build docker image
# Arguments:
#   $1: str   builder_tool, docker, buildah, podman, nerdctl
#   $2: str   tag
#   $3: str   dockerfile, if not set, use default Dockerfile in context
#   $4: str   platform, default is linux/amd64,linux/arm64
#   $5: bool  push
#   $6: array build-args array, (k1=v1 k2=v2)
#   $7: str   context
#   $8: str   sign
# Returns:
#   None
function builder () {
  local builder_tool=$1
  ## builder impl arguments
  local tag=$2
  local dockerfile=$3
  local platform=$4
  local push=$5
  local build_args=$6
  local context=$7
  ## end builder impl arguments
  local sign=$8 # Enable image signing


  local builder_impl=$(builder_factory $builder_tool)

  echo "INFO: Building image: $tag" >&2
  $builder_impl "$tag" "$dockerfile" "$platform" $push "$build_args" "$context" $sign
}


# Cosign keyless sign image
function cosign_signer () {
  local image=$1
  local upload=$2

  if [ $upload = true ]; then
    cosign sign -y $image
  else
    cosign sign -y --upload=false $image
  fi
}

# https://github.com/sigstore/cosign/issues/587

# Sign image with signer
# Arguments:
#   $1: str   image
#   $2: bool  upload, if true, upload signature to registry
#   $3: str   signer, currently only support cosign
function image_signer () {
  local image=$1
  local upload=$2
  local signer=$3

  local signer_impl

  case $signer in
    "cosign")
      signer_impl="cosign_signer"
      ;;
    *)
      echo ERROR "Unsupported signer: $signer"
      exit 1
      ;;
  esac

  echo "INFO: Signing image: $image" >&2
  $signer_impl "$image" $upload
}


# Parse product metadata.json in product path
# Arguments:
#   $1: required  product path
#   $2: optional  product version, if not set, return all versions
# Returns:
#   JSON: product metadata array
#    [
#      {
#        "tag": "quay.io/zncdatadev/airflow:1.10.12-kubedoop5.3.1",
#        "build_args": ["PRODUCT_VERSION=1.10.12", "HADOOP_VERSION=3.3.4"],
#      },
#      {
#        "tag": "quay.io/zncdatadev/airflow:1.10.12-kubedoop5.3.2",
#        "build_args": ["PRODUCT_VERSION=1.10.12", "HADOOP_VERSION=3.3.5"],
#      }
#    ]
function get_product_metadata () {
  local product_path=$1
  local filter_version=$2

  local metadata_file="$product_path/metadata.json"
  local product_name=$(jq -r '.name' $metadata_file)

  local result=()

  for property in $(jq -c '.properties[]' $metadata_file); do
    local product_version=$(echo $property | jq -r '.version')

    # if 'filter_version' set and equal to 'product_version', return result
    # else continue
    if [ -n "$filter_version" ] && [ "$filter_version" == "$product_version" ]; then
      result=($container_tool_args_json)
      break
    fi

    # container_tool_args is a list of key=value pairs for container_tool args
    local build_args=("PRODUCT_VERSION=$product_version")
    local tag="$REGISTRY/$product_name:$product_version-$PLATFORM_TAG"

    if echo $property | jq -e '.dependencies?' >> /dev/null; then
      dependencies=$(echo $property | jq -r '.dependencies')
      for key in $(echo $dependencies | jq -r 'keys[]'); do
        value=$(echo $dependencies | jq -r ".[\"$key\"]")
        key_fmt=$(echo $key | tr '[:lower:]' '[:upper:]' | tr '-' '_' | awk '{print $0"_VERSION"}')
        build_args+=("$key_fmt=$value")
      done
    fi

    local build_args_json=$(printf '%s\n' "${build_args[@]}" | jq -R . | jq -s .)
    # container_tool_args is a json object
    local container_tool_args=$(jq -n --arg tag "$tag" --argjson build_args "$build_args_json" '{tag: $tag, build_args: $build_args}')

    result+=($container_tool_args)
  done

  # Convert array to json object
  local result_json=$(printf '%s\n' "${result[@]}" | jq -s .)
  echo "INFO: Product metadata: $result_json" >&2

  # Return result json
  echo $result_json
}
