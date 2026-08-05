#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/common.sh"
require podman
IMAGE=${1:-localhost/shapebit-os:dev}

log "Checking image metadata"
podman image exists "$IMAGE"
podman run --rm "$IMAGE" test -x /usr/lib/shapebit-os/shapebit-os-info
p=$(podman run --rm "$IMAGE" cat /usr/lib/systemd/system/default.target)
[[ "$p" == *multi-user.target* ]] || die "Default target is not multi-user.target"
podman run --rm --privileged "$IMAGE" bootc container lint
log "Container checks passed"
