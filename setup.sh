#!/bin/bash

METADATA_FILE="metadata.json"

APP_NAME=$(jq  -r '.repoName' $METADATA_FILE)
APP_FULL_NAME=$(jq -r '.fullName' $METADATA_FILE)
TEMPLATE_NAME=$(jq -r '.templateName' $METADATA_FILE)

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

mv ./.github.disabled/ ./.github/

#Remove Setup File
rm ./setup.sh

#Commit the things
git add .
git commit -m "chore: run setup"

cd ./infra/
pulumi stack init dev
cd ..
