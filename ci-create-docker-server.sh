#!/usr/bin/env bash
# Based on the script from Milen Pivchev in nextcloud/ios repository

# This script starts a nextcloud test instance

echo "Creating nextcloud instance for branch $TEST_BRANCH..."

docker run --rm -d \
    --name $CONTAINER_NAME \
    -e SERVER_BRANCH=$TEST_BRANCH \
    -p $SERVER_PORT:80 \
    ghcr.io/juliushaertl/nextcloud-dev-php81:latest