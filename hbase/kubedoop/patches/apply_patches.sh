#!/bin/bash

# set -exu

function main () {
  local usage="
Usage: $(basename $0) [options] <pathes>

Apply pathes

Arguments:
  pathes          Pathes directory, required. Patch files must suffix with .patch

Options:
  -h, --help      Display this help and exit
  -s, --src       Source directory to apply pathes, default is current directory

"

  local pathes=""
  local src=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help )
        echo "$usage"
        exit 0
        ;;
      -s | --src )
        shift
        src=$1
        ;;
      * )

        if [ -n "$pathes" ]; then
          echo "Invalid argument: $1"
          echo "$usage"
          exit 1
        fi
        pathes=$1
        ;;
    esac
    shift
  done

  if [ -z "$pathes" ]; then
    echo "Pathes is required"
    echo "$usage"
    exit 1
  fi

  if [ -z "$src" ]; then
    src=$(pwd)
  fi

  echo "Apply pathes, src: $src, pathes: $pathes"

  apply_pathes $src $pathes

  echo "Apply pathes done"
}


# Apply pathes
# Arguments:
#   $1: optional  source directory
#   $2: required  pathes directory
# Return:
function apply_pathes () {
  local src=$1
  local pathes=$2

  for patch in $(ls $pathes/*.patch); do
    echo "Applying patch: $patch"
    echo "Target directory: $src"

    # 尝试检查补丁状态
    if patch --dry-run -p1 -R -d $src < $patch >/dev/null 2>&1; then
      echo "Patch appears to be already applied, skipping: $patch"
      continue
    fi

    # 强制应用补丁
    patch -f -p1 -d $src < $patch || {
      echo "Failed to apply patch: $patch"
      echo "Patch output:"
      patch --dry-run -p1 -d $src < $patch
      exit 1
    }

    echo "Successfully applied patch: $patch"
  done

}


main "$@"
