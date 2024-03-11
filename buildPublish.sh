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
docker tag temp "e36io/hyperfridge-r0:localbuild-$IMAGE_ID"
docker tag temp "e36io/hyperfridge-r0:latest"

# Push the image to Docker Hub
docker push "e36io/hyperfridge-r0:localbuild-$IMAGE_ID"
docker push "e36io/hyperfridge-r0:latest"

rm IMAGE_ID.hex
