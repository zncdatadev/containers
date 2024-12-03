#!/bin/bash

set -e
set -o pipefail

DEFAULT_PLATFORM="linux/amd64,linux/arm64"
REGISTRY=${REGISTRY:-"quay.io/zncdatadev"}
PLATFORM_VERSION=${PLATFORM_VERSION:-"0.0.0-dev"}
PLATFORM_NAME=${PLATFORM_NAME:-"kubedoop"}
PLATFORM_TAG="$PLATFORM_NAME$PLATFORM_VERSION"

CI_DEBUG=${CI_DEBUG:-false}


# Get current platform
# linux/amd64, linux/arm64
# Returns:
#   $1: str   current platform
function get_current_platform () {
  local platform
  local arch=$(uname -m)

  arch="${arch/x86_64/amd64}"
  arch="${arch/aarch64/arm64}"

  echo "INFO: Current arch: $arch" >&2
  echo "linux/$arch"
}


# Build image with docker
# Full docker command is:
# $ docker buildx build \
#     --metadata-file quay.io-zncdatadev-airflow-1.10.12-kubedoop5.3.1-digest.json \
#     --progress=plain \
#     --platform linux/amd64,linux/arm64 \
#     -t quay.io/zncdatadev/hbase:2.6.0-kubedoop5.3.1 \
#     --build-arg PRODUCT_VERSION=2.6.0 \
#     --build-arg HADOOP_VERSION=3.3.4 \
#     hbase
#
# Arguments:
#   $1: str   tag
#   $2: str   dockerfile, if not set, use default Dockerfile in context
#   $3: str   platform, default is linux/amd64,linux/arm64
#   $4: bool  push
#   $5: array build-args array, (k1=v1 k2=v2)
#   $6: str   context
# Returns:
#   $1: str   container image tag with digest if push is true
function docker_builder () {
  local tag=$1
  local dockerfile=$2
  local platform=$3
  local push=$4
  local build_args=$5
  local context=$6

  # check docker buildx context
  if ! docker buildx ls | grep -q "default"; then
    echo "INFO: Creating docker buildx context: default" >&2
    docker buildx create --name default
    docker buildx use default
  fi

  local platform_length
  if [ -z "$platform" ]; then
    platform_length=0
  else
    platform_length=$(echo $platform | tr ',' '\n' | wc -l)
  fi
  local container_tool="docker"
  local container_tool_args=("buildx" "build")
  container_tool_args+=("--tag=${tag}")
  # set docker progress to plain
  container_tool_args+=("--progress=plain")
  # save image digest to file
  local digest_file=$(echo $tag | tr '/:' '-')-digest.json
  container_tool_args+=("--metadata-file=$digest_file")

  if [ $platform_length -eq 0 ]; then
    platform=$DEFAULT_PLATFORM
    platform_length=$(echo $platform | tr ',' '\n' | wc -l)
  fi


  # if 'push' is true, use --push, else use --load
  if [ $push = true ]; then
    container_tool_args+=("--push")  # push image to registry
  else
    echo "INFO: Using local image" >&2
    platform=$(get_current_platform)
    platform_length=1
    container_tool_args+=("--load")  # load image to local, can use docker images to list
  fi

  container_tool_args+=("--platform=${platform}")

  if [ -n "$dockerfile" ]; then
    container_tool_args+=("--file=${dockerfile}")
  fi

  if [ -n "$build_args" ]; then
    for arg in $build_args; do
      container_tool_args+=("--build-arg=${arg}")
    done
  fi

  container_tool_args+=("${context}")

  # build image
  echo "INFO: Building image: $container_tool ${container_tool_args[*]}" >&2
  local cmd="$container_tool ${container_tool_args[*]}"
  if ! eval "$cmd"; then
    echo "ERROR: Failed to build image: $cmd" >&2
    exit 1
  fi

  # 检查digest文件是否存在和是否有效
  if [ ! -f "$digest_file" ]; then
    echo "ERROR: Digest file not found: $digest_file" >&2
    exit 1
  fi

  local image_digest
  if ! image_digest=$(jq -r '."containerimage.digest"' "$digest_file"); then
    echo "ERROR: Failed to get image digest from $digest_file" >&2
    exit 1
  fi

  if [ -z "$image_digest" ]; then
    echo "ERROR: Empty image digest" >&2
    exit 1
  fi

  # if CI_DEBUG is true, list images
  if [ $CI_DEBUG = true ]; then
    if [ $push = true ] && [ $platform_length -gt 1 ]; then
      echo "INFO: Inspecting manifest: $tag" >&2
      $container_tool manifest inspect $tag >&2
    else
      echo "INFO: Inspecting image: $tag" >&2
      $container_tool image inspect $tag >&2
    fi
  fi

  local digest_tag="${tag}@${image_digest}"
  echo "INFO: Image digest tag: $digest_tag" >&2
  echo $digest_tag
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
#   $7: bool  is_podman
# Returns:
#   $1: str   container image tag with digest if push is true
function buildah_backend_adaptor () {
  local tag=$1
  local dockerfile=$2
  local platform=$3
  local push=$4
  local build_args=$5
  local context=$6
  # if 'is_podman' set and true, use podman
  local is_podman=${7:-false}

  local container_tool="buildah"
  local platform_length
  if [ -z "$platform" ]; then
    platform_length=0
  else
    platform_length=$(echo $platform | tr ',' '\n' | wc -l)
  fi

  if [ $is_podman = true ]; then
    container_tool="podman"
  fi

  local buildah_args=("build")

  # if 'push' is true, and platform less then 2, use default platform
  if [ $platform_length -eq 0 ]; then
    platform=$DEFAULT_PLATFORM
  fi

  buildah_args+=("--manifest=${tag}" "--platform=${platform}" "--jobs=4")

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
  local cmd="$container_tool ${buildah_args[*]}"
  if ! eval "$cmd"; then
    echo "ERROR: Failed to build image: $cmd" >&2
    exit 1
  fi

  # if CI_DEBUG is true, list images
  if [ $CI_DEBUG = true ]; then
    if [ $platform_length -gt 1 ]; then
      echo "INFO: Inspecting manifest: $tag" >&2
      $container_tool manifest inspect $tag
    elif [ $push = true ]; then
      echo "INFO: Inspecting image: $tag" >&2
      $container_tool inspect $tag
    fi
  fi

  # if 'push' set and true, push image
  if [ $push = true ]; then
    # When use buildah or podman, digestfile is one line with image digest
    local digest_file=$(echo $tag | tr '/:' '-')-digest.txt

    # if 'platform' seted, push manifest else push image
    if [ $platform_length -gt 1 ]; then
      echo "INFO: Pushing manifest: $tag" >&2
      $container_tool manifest push --digestfile $digest_file --all $tag
    fi

    local image_digest=$(cat $digest_file)
    local digest_tag="${tag}@${image_digest}"
    echo "INFO: Image digest tag: $digest_tag" >&2
    echo $digest_tag
  else
    echo "INFO: Image tag: $tag" >&2
    echo $tag
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
# Returns:
#   $1: str   container image tag with digest if push is true
function buildah_builder () {
  local tag=$1
  local dockerfile=$2
  local platform=$3
  local push=$4
  local build_args=$5
  local context=$6

  buildah_backend_adaptor "$tag" "$dockerfile" "$platform" $push "$build_args" "$context" false
}


# Build image with podman
# Arguments:
#   $1: str   tag
#   $2: str   dockerfile
#   $3: str   platform
#   $4: bool  push
#   $5: array build-args array, (k1=v1 k2=v2)
#   $6: str   context
# Returns:
#   $1: str   container image tag with digest if push is true
function podman_builder () {
  local tag=$1
  local dockerfile=$2
  local platform=$3
  local push=$4
  local build_args=$5
  local context=$6

  buildah_backend_adaptor "$tag" "$dockerfile" "$platform" $push "$build_args" "$context" true
}


# Factory method to return builder tool
# Arguments:
#   $1: str   builder tool name,vaild docker, buildah, podman, nerdctl
# Returns:
#   $1: str   builder implementation function name (docker_builder, buildah_builder, podman_builder, nerdctl_builder)
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
# Returns:
#   $1: str   container image tag with digest if push is true
function container_builder () {
  local builder_tool=$1
  ## builder impl arguments
  local tag=$2
  local dockerfile=$3
  local platform=$4
  local push=$5
  local build_args=$6
  local context=$7
  ## end builder impl arguments

  local builder_impl
  if ! builder_impl=$(builder_factory $builder_tool); then
    echo "ERROR: Failed to get builder implementation" >&2
    exit 1
  fi

  echo "INFO: Building image: $tag" >&2

  $builder_impl "$tag" "$dockerfile" "$platform" $push "$build_args" "$context"
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

# Build docker image
# Arguments:
#   $1: str   builder_tool, docker, buildah, podman, nerdctl
#   $2: str   tag
#   $3: str   dockerfile, if not set, use default Dockerfile in context
#   $4: str   platform, default is linux/amd64,linux/arm64
#   $5: bool  push
#   $6: array build-args array, (k1=v1 k2=v2)
#   $7: str   context
#   $8: bool   sign
# Returns:
#   None
function build_sign_image () {
  local builder_tool=$1
  local tag=$2
  local dockerfile=$3
  local platform=$4
  local push=$5
  local build_args=$6
  local context=$7
  local sign=$8

  local digest_tag
  if ! digest_tag=$(container_builder $builder_tool "$tag" "$dockerfile" "$platform" $push "$build_args" "$context"); then
    echo "ERROR: Failed to build image with $builder_tool" >&2
    exit 1
  fi

  if [ -z "$digest_tag" ]; then
    echo "ERROR: Empty digest tag returned from container_builder" >&2
    exit 1
  fi

  # if 'sign' is true and 'push' is true, sign image
  if [ $sign = true ] && [ $push = true ]; then
    if ! image_signer "$digest_tag" $push "cosign"; then
      echo "ERROR: Failed to sign image: $digest_tag" >&2
      exit 1
    fi
  fi

  return 0
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

    # if 'filter_version' set and equal to 'product_version', return result
    # else continue
    if [ -n "$filter_version" ] && [ "$filter_version" == "$product_version" ]; then
      result=($container_tool_args)
      break
    fi

    result+=($container_tool_args)
  done

  # Convert array to json object
  local result_json=$(printf '%s\n' "${result[@]}" | jq -s .)
  echo "INFO: Product metadata: $result_json" >&2

  # Return result json
  echo $result_json
}
