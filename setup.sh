#!/bin/bash

METADATA_FILE="metadata.json"

function update_file {
    local file_name="$1"
    local app_name=$(jq '.repoName' $METADATA_FILE)
    local app_full_name=$(jq '.fullName' $METADATA_FILE)
    local template_name=$(jq '.templateName' $METADATA_FILE)

    sed -i -e "s/$template_name/$app_name/g" $file_name
    sed -i -e "s/{APP_NAME}/$app_full_name/g" $file_name
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

mv ./.github.disabled/ ./.github/

#Remove Setup File
rm ./setup.sh
