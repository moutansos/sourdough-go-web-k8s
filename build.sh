#!/bin/bash

DOCKER_USERNAME="mSyke"
CONTAINER_NAME="sourdough-go-web-k8s"
SCRIPT_ROOT="$(dirname "$0")"
MAIN_PROJECT="$SCRIPT_ROOT/src"
BUILD_OUTPUT_DIR="$SCRIPT_ROOT/.build_output"
TOOL_DIR="$BUILD_OUTPUT_DIR/tools"
REPO_HOST="code.msyke.dev"
BINARY_NAME="sourdough-go-web-k8s"
INFRA_BINARY_NAME="$BINARY_NAME-infra"

function dir_init {
    if [ ! -d "$BUILD_OUTPUT_DIR" ]; then
      mkdir -p "$BUILD_OUTPUT_DIR"
    fi

    if [ ! -d "$TOOL_DIR" ]; then
      mkdir -p "$TOOL_DIR"
    fi
}

build_app_flag="false"
build_infra_flag="false"
docker_build_flag="false"
docker_push_flag="false"
pulumi_preview_flag="false"
pulumi_deploy_flag="false"
local_flag="false"
gen_local_env_flag="false"
docker_container_tag="local"
env_name="dev"

function print_usage {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --app-build             Build the Application"
  echo "  --infra-build           Build the Infrastructure-as-Code Project"
  echo "  --docker-build          Build the Docker image"
  echo "  --docker-push           Push the Docker image to the registry"
  echo "  --docker-tag <tag>      Specify the Docker image tag (default: local)"
  echo "  --pulumi-preview        Build Pulumi infrastructure"
  echo "  --pulumi-deploy         Deploy Pulumi infrastructure"
  echo "  --env <environment>     Specify the deployment environment (default: dev)"
  echo "  --local                 Use local configuration"
  echo "  --gen-local-env         Generate local environment configuration"
  echo "  -h, --help              Show this help message"
  printf "\n\n"
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --app-build) build_app_flag="true" ;;
    --infra-build) build_infra_flag="true" ;;
    --docker-build) docker_build_flag="true" ;;
    --docker-push) docker_push_flag="true" ;;
    --docker-tag) docker_container_tag="$2"; shift ;;
    --pulumi-preview) pulumi_preview_flag="true" ;;
    --pulumi-publish) pulumi_publish_flag="true" ;;
    --pulumi-deploy) pulumi_deploy_flag="true" ;;
    --env) env_name="$2"; shift ;;
    --local) local_flag="true" ;;
    --gen-local-env) gen_local_env_flag="true" ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown parameter passed: $1"; print_usage; exit 1 ;;
  esac
  shift
done

function print_stage {
  local stage_name="$1"
  echo ""
  echo "=========================================="
  echo "Starting stage: $stage_name"
  echo "=========================================="
  echo ""
}

# Tool Checks

function init_plumi {
    dir_init

    if ! command -v pulumi &> /dev/null; then
        echo "Pulumi CLI not found. Installing..."
        curl -fsSL https://get.pulumi.com | sh

        export PATH="$HOME/.pulumi/bin:$PATH"
    fi

    # Check if PULUMI_ACCESS_TOKEN is set
    if [ -z "$PULUMI_ACCESS_TOKEN" ]; then
        echo "PULUMI_ACCESS_TOKEN is not set. Getting token from Bitwarden..."
        check_bitwarden_cli_installed
        export PULUMI_ACCESS_TOKEN="$(get_bitwarden_secret 'PULUMI_ACCESS_TOKEN')"
    fi
}

bws_path="$TOOL_DIR/bws"
function check_bitwarden_cli_installed {
    dir_init

    temp_path="/tmp/bws.zip"
    if [ ! -f "$bws_path" ]; then
        echo "Bitwarden CLI not found. Installing..."

        curl -L -o "$temp_path" "https://github.com/bitwarden/sdk-sm/releases/download/bws-v1.0.0/bws-x86_64-unknown-linux-gnu-1.0.0.zip"
        if [ $? -ne 0 ]; then
            echo "Failed to download Bitwarden CLI."
            exit 1
        fi

        unzip "$temp_path" -d "$TOOL_DIR"
        if [ $? -ne 0 ]; then
            echo "Failed to unzip Bitwarden CLI."
            exit 1
        fi

        chmod +x "$bws_path"
        if [ $? -ne 0 ]; then
            echo "Failed to set execute permissions on Bitwarden CLI."
            exit 1
        fi
    fi

    # check if the BWS_ACCESSS_TOKEN environment variable is set. If not prompt and then set it.
    if [ -z "$BWS_ACCESS_TOKEN" ]; then
        echo "BWS_ACCESS_TOKEN is not set. Please enter your Bitwarden access token:"
        read -s bw_token
        export BWS_ACCESS_TOKEN="$bw_token"
    fi
}

bw_project_id="79574584-9a01-45e9-b674-b24001447994"
function get_bitwarden_secret {
    local item_name="$1"

    all_secrets="$("$bws_path" secret list "$bw_project_id" --access-token "$BWS_ACCESS_TOKEN" --output json)"
    if [ $? -ne 0 ]; then
        echo "Failed to retrieve secret from Bitwarden."
        exit 1
    fi
    secret_id=$(echo "$all_secrets" | jq -r --arg NAME "$item_name" '.[] | select(.key == $NAME) | .id')
    if [ -z "$secret_id" ]; then
        echo "Secret '$item_name' not found in Bitwarden."
        exit 1
    fi

    secret_value="$("$bws_path" secret get "$secret_id" --access-token "$BWS_ACCESS_TOKEN" --output json | jq -r '.value')"
    if [ $? -ne 0 ]; then
        echo "Failed to retrieve secret value from Bitwarden."
        exit 1
    fi

    echo "$secret_value"
}

# Stages

if [[ "$build_app_flag" == "true" || "$local_flag" == "true" ]]; then
  print_stage "Building Application"
  dir_init

  go env -w GOPRIVATE=$REPO_HOST
  time go build -o $BUILD_OUTPUT_DIR/app ./src/

  if [[ "$?" -ne 0 ]]; then
      printf "\nFailed to build Application"
      exit 1
  else
      printf "\nSuccessfully built Application\n"
  fi
fi

if [[ "$build_infra_flag" == "true" || "$local_flag" == "true" ]]; then
  print_stage "Building Infrastructure-as-Code Project"
  dir_init

  go env -w GOPRIVATE=$REPO_HOST
  go env -w CGO_ENABLED=1
  go env -w CC=musl-gcc
  time go build -ldflags '-linkmode external -extldflags "-static -Wl,-unresolved-symbols=ignore-all"' -o $BUILD_OUTPUT_DIR/infra ./infra/

  if [[ "$?" -ne 0 ]]; then
    printf "\nFailed to build Infrastructure-as-Code Project\n"
    exit 1
  else
    printf "\nSuccessfully built Infrastructure-as-Code Project\n"
  fi
fi

if [[ "$docker_build_flag" == "true" || "$local_flag" == "true" ]]; then
  print_stage "Building Docker Image"

  docker build -t "$REPO_HOST/private/$CONTAINER_NAME:$docker_container_tag" .

  if [[ "$?" -ne 0 ]]; then
    printf "\nFailed to build Docker image\n"
    exit 1
  else
    printf "\nSuccessfully built Docker image\n"
  fi
fi

if [[ "$docker_push_flag" == "true" ]]; then
  print_stage "Pushing Docker Image"

  check_bitwarden_cli_installed

  echo "Pushing Docker image..."
  if [ "$docker_container_tag" == "local" ]; then
    echo "Error: Cannot push image with 'local' tag. Please specify a valid tag."
    exit 1
  fi

  full_container_tag="$REPO_HOST/private/$CONTAINER_NAME:$docker_container_tag"
  echo "Pushing image: $full_container_tag"
  DOCKER_PASSWORD=$(get_bitwarden_secret 'GITEA_PAT')
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin "$REPO_HOST/msyke"
  docker push "$full_container_tag"

  if [[ "$?" -ne 0 ]]; then
    printf "\nFailed to push Docker image\n"
    exit 1
  else
    printf "\nSuccessfully pushed Docker image\n"
  fi
fi

if [[ "$local_flag" == "true" || "$pulumi_preview_flag" == "true" ]]; then
  print_stage "Pulumi Preview"
  init_plumi

  pushd "$SCRIPT_ROOT/infra" || exit 1

  pulumi login --non-interactive
  pulumi stack select "$env_name" --non-interactive
  pulumi --non-interactive config -s dev set containerTag "$docker_container_tag"

  go env -w GOPRIVATE=$REPO_HOST
  go env -w CGO_ENABLED=1
  go env -w CC=musl-gcc
  go build -ldflags '-linkmode external -extldflags "-static -Wl,-unresolved-symbols=ignore-all"' -o bin/$INFRA_BINARY_NAME . 
  
  if [ $? -ne 0 ]; then
    echo "Failed to build Pulumi program."
    exit 1
  fi

  pulumi preview --non-interactive

  if [ $? -ne 0 ]; then
    echo "Pulumi preview failed."
    exit 1
  fi

  popd || exit 1
fi

if [ "$pulumi_deploy_flag" == "true" ]; then
  print_stage "Pulumi Deploy"
  init_plumi

  # if container tag isnt set throw error
  if [ "$docker_container_tag" == "local" ]; then
    echo "Error: Cannot deploy Pulumi with no tag. Please specify a valid --docker-tag."
    exit 1
  fi

  pushd "$SCRIPT_ROOT/infra" || exit 1

  pulumi login --non-interactive
  pulumi stack select "$env_name"
  pulumi --non-interactive config -s "$env_name" set containerTag "$docker_container_tag"

  go env -w GOPRIVATE=$REPO_HOST
  go env -w CGO_ENABLED=1
  go env -w CC=musl-gcc
  go build -ldflags '-linkmode external -extldflags "-static -Wl,-unresolved-symbols=ignore-all"' -o bin/$INFRA_BINARY_NAME . 
  
  if [ $? -ne 0 ]; then
    echo "Failed to build Pulumi program."
    exit 1
  fi

  pulumi refresh --non-interactive --yes

  if [ $? -ne 0 ]; then
    echo "Pulumi refresh failed."
    exit 1
  fi

  pulumi up --yes --non-interactive

  if [ $? -ne 0 ]; then
    echo "Pulumi deploy failed."
    exit 1
  fi

  popd || exit 1
fi

if [[ "$gen_local_env_flag" == "true" ]]; then
  print_stage "Generating Local Environment Configuration"
  check_bitwarden_cli_installed

  env_file="$SCRIPT_ROOT/src/.env"

  echo "Generating local environment file at $env_file"
  
  # Place all required environment variables here to be generated from bitwarden. 
  # Use this format: KEY=$(get_bitwarden_secret 'MY_SECRET_NAME')
  cat << EOF > "$env_file"
APP_ENV=local

# TODO: Add your environment variables here

EOF

  if [ $? -ne 0 ]; then
    echo "Failed to generate local environment file."
    exit 1
  fi

  echo "Successfully generated local environment file."
fi
    

