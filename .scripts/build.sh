#!/bin/bash

set -e
set -o pipefail


CI_DEBUG=${CI_DEBUG:-false}
REGISTRY=${REGISTRY:-"quay.io/zncdatadev"}
CACHE_REGISTRY=${CACHE_REGISTRY:-$REGISTRY}
KUBEDOOP_VERSION=${KUBEDOOP_VERSION:-"0.0.0-dev"}
KUBEDOOP_TAG="kubedoop${KUBEDOOP_VERSION}"

# Allowed platforms for build (comma-separated). Can be overridden via env.
# Keep this in sync with supported Docker platforms in the project.
ALLOW_PLATFORM=${ALLOW_PLATFORM:-"linux/amd64,linux/arm64"}

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
  Build specified product and specified version:
    ${cmd_name} java-base:17 hadoop:3.3.1

Options:
  -r,   --registry REGISTRY       Set the registry, default is 'quay.io/zncdatadev'
        --platform PLATFORM       Set the build platform(s). If not set, use current system arch.
                                  Multiple platforms can be specified, separated by comma.
                                    Example: 'linux/amd64,linux/arm64'
  -p,   --push                    Push the built image to the registry, if not set, load the image to local docker
  -s,   --sign                    Sign the image with cosign
        --progress PROGRESS       Set the build progress output format. Default is 'auto'.
                                  Use 'plain' for plain text output, useful for debugging.
        --arch-suffix             Use architecture suffix for image tags when pushing to registry.
                                  This is useful when building multi-arch images.
                                  Note: this option is ignored if --platform specifies multiple platforms.
  -h,   --help                    Show this message
"

  local registry=$REGISTRY
  local progress="" # Default progress mode for docker buildx bake
  local push=false
  local sign=false
  local platform_input="" # Raw --platform string from CLI
  local arch_suffix=false # Use architecture suffix for image tags
  # Change target to array
  local -a products=()

  # Parse arguments
  while [ "$1" != "" ]; do
    case $1 in
      -r | --registry )
        shift
        registry=$1
        ;;
      --platform )
        shift
        platform_input=$1
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
        fi
        ;;
      --arch-suffix )
        arch_suffix=true
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

  # Print all specified products
  if [ ${#products[@]} -gt 0 ]; then
    echo "INFO: Specified products: ${products[*]}" >&2
  fi

  # Check system requirements if signing is requested
  system_requirements $sign

  # Resolve platforms: if --platform provided, use it; otherwise default to current system architecture
  local platforms=""
  if [ -n "$platform_input" ]; then
    # If not pushing and user requested multiple platforms, fall back to single-arch due to --load limitation
    if [ "$push" = false ] && [[ "$platform_input" == *","* ]]; then
      echo "WARNING: --platform specifies multiple platforms but --push is not set.\n         Falling back to current system architecture for --load builds." >&2
      platforms="$(current_platform_json)"
    else
      platforms="$(platforms_to_json "$platform_input")"
    fi
  else
    platforms="$(current_platform_json)"
  fi
  echo "INFO: Build platforms: $platforms" >&2

  # Fill in product versions
  products=($(fill_products_version "${products[@]}"))
  echo "INFO: Specified products with versions: ${products[*]}" >&2

  # Get the bakefile configuration
  local bakefile=$(get_bakefile "$platforms" "$arch_suffix")

  # Update function call order of parameters
  build_sign_image "$bakefile" $push $sign "$progress" "${products[*]}"
}


# Check system requirements
# Arguments:
#   $1: bool  sign, if true, check cosign is installed
# Returns:
#   None, exit if requirements not met
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


# Fill in product versions from products.
# The value of product may be "java-base:17" or "hadoop".
# If a specific version is present, no processing is needed;
# if not, read all product versions from the corresponding `<product>/versions.yaml` file
# in the directory and append them to the product name.
# Arguments:
#   $1: str   products, the product name
# Returns:
#   str      filled_products, the product name with version
function fill_products_version () {
  local products=$1
  local filled_products=()

  for product in $products; do
    if [[ "$product" =~ : ]]; then
      # If product has a specific version, no need to process
      filled_products+=("$product")
    else
      # If no specific version, read from versions.yaml
      local version_file="$product/versions.yaml"
      if [[ -f "$version_file" ]]; then
        local versions=$(yq eval '.versions[].product' "$version_file")
        if [ -n "$versions" ]; then
          for version in $versions; do
            filled_products+=("$product:$version")
          done
        else
          echo "WARNING: No product versions found in '$version_file'" >&2
        fi
      else
        echo "WARNING: Version file not found for product '$product' in '$version_file'" >&2
      fi
    fi
  done

  echo "${filled_products[@]}"
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

  # Ensure the bakefile is not empty
  if [[ -z "$bakefile" ]]; then
    echo "ERROR: Bakefile is empty. Cannot proceed with building the image." >&2
    exit 1
  fi

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
  elif [ "$CI_DEBUG" = "true" ]; then
    # In debug mode, default to plain to see the output in CI logs
    cmd+=("--progress" "plain")
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

  if [ "$push" = false ]; then
    # When using --load, the image will be loaded into the local docker.
    # We can check the loaded images to ensure it was successful.
    echo "INFO: Loaded images into local docker. You can verify with 'docker images'." >&2
  else
    # When using --push, the image should be pushed to the registry.
    if [ ! -f "$image_digest_file" ]; then
      echo "ERROR: Metadata file '$image_digest_file' not found after pushing images." >&2
      exit 1
    fi

    # Check if the push was successful by verifying the digest file exists
    echo "INFO: Successfully pushed images to registry: $REGISTRY" >&2
  fi

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

    echo "INFO: Finished signing images." >&2
  fi
}


# Construct docker bake file using project.yaml and versions.yaml in product path.
# Docker bake file reference: https://docs.docker.com/build/bake/reference/
# The bake file is a JSON object
# Arguments:
#   $1: str, platforms, platforms for bakefile. eg: '["linux/amd64", "linux/arm64"]'
#   $2: bool, arch_suffix, whether to add architecture suffix to tags for single-platform builds
# Returns:
#   JSON: bake file JSON object
#
function get_bakefile () {
  local platforms=$1
  local arch_suffix=$2

  # if platforms is empty, set default value
  if [ -z "$platforms" ]; then
    echo "ERROR: platforms is empty" >&2
    exit 1
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

      # Iterate over versions to construct targets and groups
      for version in $(echo "$versions" | jq -c '.[]'); do
        # Construct bakefile target object
        local target=$(jq -n '{}')

        local product_version=$(echo "$version" | jq -r '.product')
        # Transform target name, eg: kubedoop-0_0_0_dev
        local target_name="${product_name}-$(echo "$product_version" | tr '.' '_')"
        # Add target to product groups
        product_groups=$(echo "$product_groups" | jq --arg name "$target_name" '. + [$name]')

        # Construct tags object
        local base_tag="$REGISTRY/$product_name:$product_version-$KUBEDOOP_TAG"

        # Add architecture suffix if requested and building single platform
        if [ "$arch_suffix" = true ]; then
          local platform_count=$(echo "$platforms" | jq 'length')
          if [ "$platform_count" -eq 1 ]; then
            local single_platform=$(echo "$platforms" | jq -r '.[0]')
            local arch_part=$(echo "$single_platform" | cut -d'/' -f2)
            base_tag="${base_tag}-${arch_part}"
          fi
        fi

        local tags=$(jq -n --arg tag "$base_tag" '[$tag]')
        target=$(echo "$target" | jq --arg k "tags" --argjson v "$tags" '. + {($k): $v}')

        # Construct contexts object
        local contexts=$(jq -n '{}')
        target=$(echo "$target" | jq --arg k "context" --arg v "$product_name" '. + {($k): $v}')

        # Construct args and contexts object
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
        target=$(echo "$target" | jq --arg k "contexts" --argjson v "$contexts" '. + {($k): $v}')

        # Add cache-from and cache-to for registry caching
        # https://docs.docker.com/build/cache/backends/registry/
        local cache_from="type=registry,mode=max,ref=$CACHE_REGISTRY/cache:$product_name-$product_version"
        target=$(echo "$target" | jq --arg k "cache-from" --arg v "$cache_from" '. + {($k): [$v]}')
        local cache_to="type=registry,mode=max,compression=zstd,ignore-error=true,oci-mediatypes=true,image-manifest=true,ref=$CACHE_REGISTRY/cache:$product_name-$product_version"
        target=$(echo "$target" | jq --arg k "cache-to" --arg v "$cache_to" '. + {($k): [$v]}')

        local datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Construct labels object
        local labels=$(jq -n '{}')
        labels=$(echo "$labels" | jq --arg k "org.opencontainers.image.title" --arg v "$product_name" '. + {($k): $v}')
        labels=$(echo "$labels" | jq --arg k "org.opencontainers.image.version" --arg v "$product_version" '. + {($k): $v}')
        labels=$(echo "$labels" | jq --arg k "org.opencontainers.image.created" --arg v "$datetime" '. + {($k): $v}')
        labels=$(echo "$labels" | jq --arg k "org.opencontainers.image.revision" --arg v "$current_sha" '. + {($k): $v}')
        target=$(echo "$target" | jq --argjson v "$labels" '. + {labels: $v}')

        # Construct annotations object
        local annotations=$(jq -n '[]')
        annotations=$(echo "$annotations" | jq --arg k "org.opencontainers.image.created=$datetime" '. + [$k]')
        annotations=$(echo "$annotations" | jq --arg k "org.opencontainers.image.revision=$current_sha" '. + [$k]')
        target=$(echo "$target" | jq --argjson v "$annotations" '. + {annotations: $v}')

        # Add platforms and dockerfile to target
        target=$(echo "$target" | jq --arg k "platforms" --argjson v "$platforms" '. + {($k): $v}')
        target=$(echo "$target" | jq --arg k "dockerfile" --arg v "Dockerfile" '. + {($k): $v}')
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

# -------------------- helpers --------------------
# Convert a comma-separated platform list to JSON array accepted by bake
# Arguments:
#   $1: str, platforms, comma-separated platform list, eg:
#  - linux/amd64,linux/arm64
#  - linux/arm64
# Returns:
#   JSON: platforms, JSON array of platforms, eg:
#  - ["linux/amd64","linux/arm64"]
function platforms_to_json () {
  local platform_input="$1"
  if [ -z "$platform_input" ]; then
    echo '[]'
    return 0
  fi

  local result='[]'
  IFS=',' read -r -a platform_array <<< "$platform_input"
  IFS=',' read -r -a allowed_arr <<< "$ALLOW_PLATFORM"
  for p in "${platform_array[@]}"; do
    p=$(echo "$p" | xargs) # trim spaces
    local ok=false
    for ap in "${allowed_arr[@]}"; do
      ap=$(echo "$ap" | xargs)
      if [ "$p" = "$ap" ]; then
        ok=true
        break
      fi
    done
    if [ "$ok" != true ]; then
      echo "ERROR: Unsupported platform value: '$p'. Allowed: $ALLOW_PLATFORM" >&2
      exit 1
    fi
    result=$(echo "$result" | jq --arg v "$p" '. + [$v]')
  done
  echo $(jq -c '.' <<< "$result")
}


# Get current system architecture as JSON array with one element
function current_platform_json () {
  local arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)
      local def='linux/amd64' ;;
    aarch64|arm64)
      local def='linux/arm64' ;;
    *)
      echo "ERROR: Unsupported local architecture: $arch" >&2
      exit 1 ;;
  esac
  # Ensure default platform is in ALLOW_PLATFORM
  if ! (echo "$ALLOW_PLATFORM" | tr ',' '\n' | grep -qx "$def"); then
    echo "ERROR: Default platform '$def' (from arch '$arch') is not in ALLOW_PLATFORM: $ALLOW_PLATFORM" >&2
    exit 1
  fi
  echo "[\"$def\"]"
}


main "$@"
