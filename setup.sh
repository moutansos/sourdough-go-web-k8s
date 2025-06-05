#!/bin/bash

APP_NAME="$1"
APP_FULL_NAME="$2"

TEMPLATE_NAME="sourdough-go-web-k8s"

function update_file {
    local file_name="$1"
    sed -i -e "s/$TEMPLATE_NAME/$APP_NAME/g" $file_name
    sed -i -e "s/{APP_NAME}/$APP_FULL_NAME/g" $file_name
}

GIT_IGNORED = ""
# Recursively find all files
find . -type f | while read -r file; do
    # echo "Checking file: $file"
    GIT_IGNORED=$(git check-ignore $file)
    if [[ $file == "./setup.sh" ]]; then
        continue
    elif [[ $GIT_IGNORED != "" ]]; then
        continue
    elif [[ $file = ./.git/* ]]; then
        continue
    fi

    echo "Processing: $file"

    update_file $file
done

#Setup the README
rm ./README.md
mv ./README.template.md ./README.md

#Remove Setup File
rm ./setup.sh
