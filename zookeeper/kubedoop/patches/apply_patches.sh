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
    echo "Apply patch: $patch"
    patch -p1 -d $src < $patch || {
      echo "Apply patch failed: $patch"
      exit 1
    }
    # git apply --directory=$src $patch || {
    #   echo "Apply patch failed: $patch"
    #   exit 1
    # }
  done

}


main "$@"
