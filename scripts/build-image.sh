#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require podman
IMAGE=${1:-localhost/shapebit-os:dev}
FEDORA_VERSION=${FEDORA_VERSION:-44}
log "Building $IMAGE from Fedora $FEDORA_VERSION"
podman build --build-arg "FEDORA_VERSION=$FEDORA_VERSION" -t "$IMAGE" -f Containerfile .
