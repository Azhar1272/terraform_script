#!/bin/bash

# Define your ECR repository name and tag
IMAGE='snowpipe-scheduling'
TAG="latest"
REGION=${AWS_DEFAULT_REGION}
PYTHON_VERSION='python3.9'
FUNCTION_NAME='snowpipe-scheduling-function'

# Build the Docker image and tag it
docker build -t $ECR_REPO_NAME/$IMAGE:$TAG --platform=linux/amd64 --build-arg PYTHON_VERSION=$PYTHON_VERSION .

# Get the ECR login command and execute it
aws ecr get-login --no-include-email --region $REGION

# Push the Docker image to the ECR repository
docker push $ECR_REPO_NAME/$IMAGE:$TAG

# Updating the Lambda
aws lambda update-function-code --region $REGION --function-name $FUNCTION_NAME --image-uri $ECR_REPO_NAME/$IMAGE:$TAG

