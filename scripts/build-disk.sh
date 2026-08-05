#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require podman
IMAGE=${1:-localhost/shapebit-os:dev}
OUTPUT=${2:-build/shapebit-os.qcow2}
mkdir -p "$(dirname "$OUTPUT")" build/bib-output

cat > build/config.toml <<'TOML'
[[customizations.user]]
name = "shapebit"
password = "shapebit"
groups = ["wheel"]

[customizations.kernel]
append = "console=tty0 console=ttyS0,115200n8"
TOML

log "Creating QCOW2 with bootc-image-builder"
log "Developer credentials: shapebit / shapebit"

# bootc-image-builder currently writes into /output.
podman run --rm --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$PWD/build/config.toml:/config.toml:ro,Z" \
  -v "$PWD/build/bib-output:/output:Z" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --config /config.toml \
  "$IMAGE"

FOUND=$(find build/bib-output -type f -name '*.qcow2' -print -quit)
[[ -n "$FOUND" ]] || die "bootc-image-builder did not produce a QCOW2 file"
cp --reflink=auto "$FOUND" "$OUTPUT"
log "Disk image: $OUTPUT"
log "Note: explicit systemd-boot installation will be validated in the installer backend path."
