#!/bin/bash

set APP_NAME = $1
set TEMPLATE_NAME = "sourdough-go-web-k8s"

function update_file {
    local file_name="$1"
    sed "s/$TEMPLATE_NAME/$APP_NAME/g" $file_name
}

# Recursively find all files
find . -type f | while read -r file; do
    local git_file_exists=$(git check-ignore $file_name)
    if [ $file == "./setup.sh" ]; then
        continue
    elif [ $git_file_exists == "" ]; then
        continue
    fi
    echo "Processing: $file"

    update_file $file
done
