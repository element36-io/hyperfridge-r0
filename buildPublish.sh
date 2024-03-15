#!/bin/bash
set -e


docker login

# Build the Docker image
docker buildx build --load . -t temp

# Create a temporary container from the image
CONTAINER_ID=$(docker create temp)
echo "container-id $CONTAINER_ID"

# Copy the IMAGE_ID.hex file from the container to the host
docker cp $CONTAINER_ID:/app/IMAGE_ID.hex ./IMAGE_ID.hex



# Read the content of IMAGE_ID.hex
IMAGE_ID=$(cat IMAGE_ID.hex)
echo "image-id $IMAGE_ID"

# Tag the image with IMAGE_ID
docker tag temp e36io/hyperfridge-r0:macos-$IMAGE_ID
docker push     e36io/hyperfridge-r0:macos-$IMAGE_ID
echo "push as macos latest"
docker tag temp e36io/hyperfridge-r0:macos-latest
docker push     e36io/hyperfridge-r0:macos-latest
docker rm $CONTAINER_ID
rm IMAGE_ID.hex

echo "image pushed. "
