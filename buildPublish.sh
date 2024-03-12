#!/bin/bash
set -e

docker login

# Build the Docker image
docker buildx build . -t temp

# Create a temporary container from the image
CONTAINER_ID=$(docker create temp)

# Copy the IMAGE_ID.hex file from the container to the host
docker cp $CONTAINER_ID:/app/IMAGE_ID.hex ./IMAGE_ID.hex

# Remove the temporary container
docker rm $CONTAINER_ID

# Read the content of IMAGE_ID.hex
IMAGE_ID=$(cat IMAGE_ID.hex)

# Tag the image with IMAGE_ID
docker tag temp "e36io/hyperfridge-r0:macos-$IMAGE_ID"
docker tag temp "e36io/hyperfridge-r0:macos-latest"

# Push the image to Docker Hub
docker push "e36io/hyperfridge-r0:macos-$IMAGE_ID"
docker push "e36io/hyperfridge-r0:macos-latest"

rm IMAGE_ID.hex


if [ $# -ne 1 ]; then
    echo "default release name to macos-$IMAGE_ID"
    RELEASE_NAME="macos-$IMAGE_ID"
else
    RELEASE_NAME="$1-$IMAGE_ID"
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "GitHub token GITHUB_TOKEN not found in environment variables, will not publish release on github."
    exit 1
fi

RELEASE_DIR="./release"
mkdir -p "$RELEASE_DIR"
GITHUB_TOKEN="$GITHUB_TOKEN"
REPO="element36-io/hyperfridge-r0"
ZIP_FILE="macos-release.zip"

# Copy the IMAGE_ID.hex file from the container to the host
docker cp $CONTAINER_ID:/app/IMAGE_ID.hex ./release/IMAGE_ID.hex
docker cp $CONTAINER_ID:/target/release/host ./release/host
docker cp $CONTAINER_ID:/target/release/verifier ./release/verifier
docker cp $CONTAINER_ID:/target/riscv-guest/riscv32im-risc0-zkvm-elf/release/hyperfridge  ./release/hyperfridge
docker cp $CONTAINER_ID:/data ./release/data

# Create release.zip
echo "Creating release.zip..."
zip -r "$ZIP_FILE" "$RELEASE_DIR"

# Create a release
echo "Creating release $RELEASE_NAME..."
response=$(curl -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"$RELEASE_NAME\",\"name\":\"$RELEASE_NAME\",\"body\":\"Release $RELEASE_NAME\",\"draft\":false,\"prerelease\":false}" \
    "https://api.github.com/repos/$REPO/releases")

# Get the release ID from the response
release_id=$(echo "$response" | jq -r '.id')

if [ -z "$release_id" ]; then
    echo "Failed to create release."
    exit 1
fi

# Upload the zip file
echo "Uploading zip file $ZIP_FILE..."
curl -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/zip" \
    --data-binary "@$ZIP_FILE" \
    "https://uploads.github.com/repos/$REPO/releases/$release_id/assets?name=$(basename $ZIP_FILE)"

echo "Release published successfully on github."