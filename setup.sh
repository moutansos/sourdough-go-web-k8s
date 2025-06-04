#!/bin/bash

set APP_NAME = $1
set TEMPLATE_NAME = "sourdoug-go-web-k8s"

function update_file {
    local file_name = $1
    sed "s/$TEMPLATE_NAME/$APP_NAME/g" $file_name
}

# Recursively find all files
find . -type f | while read -r file; do
    if [ $file == "./setup.sh" ]; then
        continue
    fi
    echo "Processing: $file"

done
