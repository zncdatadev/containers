#!/bin/bash

CHANGED_PRDUCT=$(git diff --name-only | grep -E '^[^/]+/config.json')


for config in $CHANGED_PRDUCT; do
  echo $(jq -r '.name' $config)
  jq -r '.versions[] | to_entries[] | "\(.key) \(.value)"' $config | while read -r key value; do
    echo "Key: $key, Value: $value"
  done
done
