#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require podman
IMAGE=${1:-localhost/shapebit-os:dev}
log "Running bootc container lint"
podman run --rm --privileged "$IMAGE" bootc container lint
