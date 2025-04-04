#!/bin/bash

set -e
set -o pipefail


CI_DEBUG=${CI_DEBUG:-false}
REGISTRY=${REGISTRY:-"quay.io/zncdatadev"}
CACHE_REGISTRY=${CACHE_REGISTRY:-$REGISTRY}
KUBEDOOP_VERSION=${KUBEDOOP_VERSION:-"0.0.0-dev"}
KUBEDOOP_TAG="kubedoop${KUBEDOOP_VERSION}"

PATH=$PATH:$(pwd)/bin


# If CI_DEBUG is set, enable debug mode
if [ "$CI_DEBUG" = "true" ]; then
  set -x
fi


function main () {
  local cmd_name=$(basename $0)
  local usage="
Usage: ${cmd_name} [OPTIONS] [PRODUCT...]

Build the image.

Use docker buildx bake to build the image, and push the image to the registry.

Examples:
  Build all products:
    ${cmd_name}
  Build specified product:
    ${cmd_name} java-base
  Build specified products
    ${cmd_name} java-base hadoop
  Build specified product and specified version:
    ${cmd_name} java-base:17 hadoop:3.3.1
  Build and push the image:
    ${cmd_name} --push hadoop

Options:
  -r,  --registry REGISTRY        Set the registry, default is 'quay.io/zncdatadev'
  -p,  --push                     Push the built image to the registry, if not set, load the image to local docker
  -s,  --sign                     Sign the image with cosign
       --progress <plain|auto|tty>  Set the build progress output format. Default is 'auto'.
                                   Use 'plain' for plain text output, useful for debugging.

  -h,  --help                     Show this message
"

  local registry=$REGISTRY
  local progress="auto" # Default progress mode for docker buildx bake
  local push=false
  local sign=false
  # Change target to array
  local -a products=()

  # Parse arguments
  while [ "$1" != "" ]; do
    case $1 in
      -r | --registry )
        shift
        registry=$1
        ;;
      -h | --help )
        echo "$usage"
        exit 0
        ;;
      -p | --push )
        push=true
        ;;
      -s | --sign )
        sign=true
        ;;
      --progress )
        shift
        # Validate the progress option
        if [[ "$1" =~ ^(plain|auto|tty)$ ]]; then
          progress=$1
        else
          echo "Error: Invalid progress format '$1'. Valid options are 'plain', 'auto', or 'tty'."
          exit 1
        fi
        ;;
      * )
        # Handle non-option argument as target
        if [[ $1 != -* ]]; then
          products+=("$1")
        else
          echo "Error: Invalid argument '$1'"
          echo "$usage"
          exit 1
        fi
        ;;
    esac
    shift
  done

  # Set registry
  export REGISTRY=$registry

  # Print all specified targets
  if [ ${#targets[@]} -gt 0 ]; then
    echo "INFO: Specified targets: ${targets[*]}"
  fi

  # Check system requirements if signing is requested
  system_requirements $sign


  # Note:
  # If push is not true, we use single-architecture to build the image.
  # The docker version in Ubuntu 24.04 of the current GitHub runner does not
  # support multi-architecture image building with the --load parameter.
  # Moreover, if push is false, we do not need to build multi-architecture images,
  # just load the current system architecture image into docker with the --load parameter.
  local platforms='["linux/amd64", "linux/arm64"]'
  if [ "$push" = false ]; then
    platforms='["linux/'$(uname -m)'"]'
  fi

  # Get the bakefile configuration
  local bakefile=$(get_bakefile "$platforms")

  # Update function call order of parameters
  build_sign_image "$bakefile" $push $sign $progress "${products[*]}"
}


function system_requirements () {
  local sign=$1

  if ! command -v jq > /dev/null; then
    echo "jq is required. Please install it refer to <https://stedolan.github.io/jq/download/>" >&2
    exit 1
  fi

  if ! command -v yq > /dev/null; then
    echo "yq is required. Please install it refer to <https://mikefarah.gitbook.io/yq/>" >&2
    exit 1
  fi

  if [ "$sign" = true ] && ! command -v cosign > /dev/null; then
    echo "cosign is required, Please install it refer to <https://docs.sigstore.dev/cosign/system_config/installation/>" >&2
    exit 1
  fi
}


# https://github.com/sigstore/cosign/issues/587
# Use Cosign for keyless image signing
function sign_image () {
  local image=$1
  local upload=$2

  # Verify that image is not null before signing
  if [[ -z "$image" || "$image" == *"null"* ]]; then
    echo "ERROR: Invalid image reference for signing: '$image'" >&2
    return 1
  fi

  if [ "$upload" = true ]; then
    echo "INFO: Signing image with OIDC token: $image" >&2
    cosign sign --yes $image
  else
    echo "INFO: Image signing skipped (upload=false): $image" >&2
  fi
}


# Build image with docker bake
# Arguments:
#  $1: str   bakefile, docker bake file content, JSON object
#  $2: bool  push, if true, push image to registry, else load to local docker, default is false
#  $3: bool  sign, if true, sign image with cosign, default is false
#  $4: str   progress, if set to 'plain', will show the build progress in plain text.
#             This is useful for debugging purposes. Default is empty, which uses the default progress format.
#  $5: str   products, products to build, if empty, build all products.
#             A version can be specified with the product name.
#             eg: 'java-base hadoop:3.3.1'
# Returns:
#  None
function build_sign_image () {
  local bakefile=$1
  local push=$2
  local sign=$3
  local progress=$4
  local products=$5

  local image_digest_file="docker-bake-digests.json"
  local cmd=("docker" "buildx" "bake")

  if [ "$push" = true ]; then
    cmd+=("--push")
  else
    cmd+=("--load")
  fi

  # Allow setting the progress mode, default is empty which uses the default progress format
  if [ -n "$progress" ]; then
    cmd+=("--progress" "$progress")
  fi

  cmd+=("--metadata-file" $image_digest_file)
  cmd+=("--file" "-")

  local -a to_build_targets=()
  # Add all targets to command
  for product in $products; do
    if [ -n "$product" ]; then
      # Transform target if it contains colon and dot
      if [[ "$product" == *:* ]]; then
        target=$(echo "$product" | sed 's/:/-/g' | sed 's/\./_/g')
      fi
      to_build_targets+=("$target")
    fi
  done

  if [ ${#to_build_targets[@]} -gt 0 ]; then
    echo "INFO: Building targets: ${to_build_targets[*]}" >&2
    cmd+=("${to_build_targets[@]}")
  else
    echo "INFO: Building all targets" >&2
  fi

  echo "INFO: Building image: ${cmd[*]}" >&2
  echo "$bakefile" | "${cmd[@]}"

  # Only attempt signing if requested and when pushing images
  if [ -f "$image_digest_file" ] && [ "$sign" = true ] && [ "$push" = true ]; then
    echo "INFO: Signing images from digest file: $image_digest_file" >&2

    # First dump file content for debugging
    if [ "$CI_DEBUG" = "true" ]; then
      echo "DEBUG: Contents of $image_digest_file:" >&2
      cat "$image_digest_file" >&2
    fi

    for key in $(jq -r 'keys[]' "$image_digest_file"); do
      echo "INFO: Processing image entry for key: $key" >&2
      local image_digest=$(jq -r --arg key "$key" '.[$key]["containerimage.digest"] // empty' "$image_digest_file")
      local image_name=$(jq -r --arg key "$key" '.[$key]["image.name"] // empty' "$image_digest_file")

      # More comprehensive checks
      if [[ -n "$image_digest" && "$image_digest" != "null" && -n "$image_name" && "$image_name" != "null" ]]; then
        local digest_tag="${image_name}@${image_digest}"
        echo "INFO: Preparing to sign image: $digest_tag" >&2
        sign_image "$digest_tag" "$push"
      else
        echo "WARNING: Skipping invalid image entry for key '$key'. Name: '$image_name', Digest: '$image_digest'" >&2
      fi
    done
  else
    [ "$sign" = true ] && echo "INFO: Image signing skipped (no digest file or push=false)" >&2
  fi
}


# Get docker bake file using project.yaml and versions.yaml in product path
# The bake file is a JSON object
# Arguments:
#   $1: str, platforms, platforms for bakefile. eg: '["linux/amd64", "linux/arm64"]'
# Returns:
#   JSON: bake file JSON object
#
function get_bakefile () {
  local platforms=$1

  # if platforms is empty, set default value
  if [ -z "$platforms" ]; then
    platforms='["linux/'$(uname -m)'"]'
  fi

  local current_sha=$(git rev-parse HEAD)

  # Use yq to parse yaml file to json
  local products=$(yq eval '.products' -o=json project.yaml)
  local bakefile=$(jq -n '{group:{}, target: {}}')
  local default_groups=$(jq -n '[]')

  for product_name in $(echo "$products" | jq -r '.[]'); do
    local versions_file="${product_name}/versions.yaml"
    echo "INFO: Process product versions file: $versions_file" >&2
    if [ -f $versions_file ]; then

      # add product to default_groups
      default_groups=$(echo "$default_groups" | jq --arg name "$product_name" '. + [$name]')

      local product_groups=$(jq -n '[]')

      local versions=$(yq eval '.versions' -o=json $versions_file)
      local targets=$(jq -n '{}')
      for version in $(echo "$versions" | jq -c '.[]'); do

        # Construct bakefile target object
        local target=$(jq -n '{}')

        local product_version=$(echo "$version" | jq -r '.product')
        # Transform target name, eg: kubedoop-0_0_0_dev
        local target_name="${product_name}-$(echo "$product_version" | tr '.' '_')"
        # Add target to product groups
        product_groups=$(echo "$product_groups" | jq --arg name "$target_name" '. + [$name]')

        local tags=$(jq -n --arg tag "$REGISTRY/$product_name:$product_version-$KUBEDOOP_TAG" '[$tag]')

        # Construct contexts object
        local contexts=$(jq -n '{}')

        # Construct args object
        local args=$(jq -n '{}')
        for dependency in $(echo "$version" | jq -r 'keys[]'); do
          # get value by dependency key
          value=$(echo "$version" | jq -r --arg k "$dependency" '.[$k]')
          # When dependency is in products, it is a context for target, should:
          #  - Add to contexts
          if echo "$products" | jq -e --arg k "$dependency" '. | index($k)' > /dev/null; then
            local contexts_target_key="zncdatadev/image/$dependency"
            local contexts_target_value="target:$dependency-$(echo $value | tr '.' '_')"
            contexts=$(echo "$contexts" | jq --arg k "$contexts_target_key" --arg v "$contexts_target_value" '. + {($k): $v}')
          fi

          # Transform dependency name to uppercase and replace - with _, append _VERSION
          # eg: INOTIFY_TOOLS_VERSION
          local transformed_key=$(echo "$dependency" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"_VERSION"
          # append dependency to 'args'
          args=$(echo "$args" | jq --arg k "$transformed_key" --arg v "$value" '. + {($k): $v}')
        done

        target=$(echo "$target" | jq --arg k "args" --argjson v "$args" '. + {($k): $v}')
        target=$(echo "$target" | jq --arg k "platforms" --argjson v "$platforms" '. + {($k): $v}')
        target=$(echo "$target" | jq --arg k "tags" --argjson v "$tags" '. + {($k): $v}')
        target=$(echo "$target" | jq --arg k "context" --arg v "$product_name" '. + {($k): $v}')
        target=$(echo "$target" | jq --arg k "dockerfile" --arg v "Dockerfile" '. + {($k): $v}')
        # If contexts is not empty, add to target
        if [ "$contexts" != "{}" ]; then
          target=$(echo "$target" | jq --arg k "contexts" --argjson v "$contexts" '. + {($k): $v}')
        fi

        # https://docs.docker.com/build/cache/backends/registry/
        local cache_from="type=registry,mode=max,ref=$CACHE_REGISTRY/cache:$product_name-$product_version"
        target=$(echo "$target" | jq --arg k "cache-from" --arg v "$cache_from" '. + {($k): [$v]}')
        local cache_to="type=registry,mode=max,compression=zstd,ignore-error=true,oci-mediatypes=true,image-manifest=true,ref=$CACHE_REGISTRY/cache:$product_name-$product_version"
        target=$(echo "$target" | jq --arg k "cache-to" --arg v "$cache_to" '. + {($k): [$v]}')

        local datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        local labels=$(jq -n '{}')
        labels=$(echo "$labels" | jq --arg k "org.opencontainers.image.title" --arg v "$product_name" '. + {($k): $v}')
        labels=$(echo "$labels" | jq --arg k "org.opencontainers.image.version" --arg v "$product_version" '. + {($k): $v}')
        labels=$(echo "$labels" | jq --arg k "org.opencontainers.image.created" --arg v "$datetime" '. + {($k): $v}')
        labels=$(echo "$labels" | jq --arg k "org.opencontainers.image.revision" --arg v "$current_sha" '. + {($k): $v}')
        target=$(echo "$target" | jq --argjson v "$labels" '. + {labels: $v}')

        local annotations=$(jq -n '[]')
        annotations=$(echo "$annotations" | jq --arg k "org.opencontainers.image.created=$datetime" '. + [$k]')
        annotations=$(echo "$annotations" | jq --arg k "org.opencontainers.image.revision=$current_sha" '. + [$k]')
        target=$(echo "$target" | jq --argjson v "$annotations" '. + {annotations: $v}')

        # Add target to targets
        targets=$(echo "$targets" | jq --arg k "$target_name" --argjson v "$target" '. + {($k): $v}')

      done
    fi
    echo "INFO: Processed product targets: $product_name: $(echo "$product_groups" | jq -c '.')" >&2
    # Add product groups to group
    bakefile=$(echo "$bakefile" | jq --arg k "$product_name" --argjson v "$product_groups" '.group |= . + {($k): {targets: $v}}')

    # Add targets to bakefile
    bakefile=$(echo "$bakefile" | jq --argjson v "$targets" '.target |= . + $v')
  done

  echo "INFO: default targets: $(echo "$default_groups" | jq -c '.')" >&2
  # Add default groups to bakefile
  bakefile=$(echo "$bakefile" | jq --arg k "default" --argjson v "$default_groups" '.group |= . + {($k): {targets: $v}}')

  # Save bakefile to bakefile.json
  jq -r '.' <<< $bakefile > ./bakefile.json

  echo $(jq -c '.' <<< $bakefile)
}


main "$@"
