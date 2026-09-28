#!/usr/bin/env bash
# Install the image archive from image.sh to the raw disk DISK and save its
# recovery key to RECOVERY_KEY. The storage layout and install run inside the
# image (scripts/install.sh).
# Usage: disk.sh (called by `make disk`).
set -euo pipefail
: "${ENGINE:?}" "${IMAGE:?}" "${BUILD:?}" "${DISK:?}" "${DISK_SIZE:?}" "${RECOVERY_KEY:?}"

archive=$BUILD/image.tar
[[ -f $archive ]] || { echo "error: $archive not found; run 'make image'" >&2; exit 1; }

# A new disk is a new machine: fresh EFI variables and TPM (see vm.sh).
rm -rf "$DISK" "$RECOVERY_KEY" "$BUILD/efivars.fd" "$BUILD/tpm"
truncate -s "$DISK_SIZE" "$DISK"
mkdir -p "$(dirname "$RECOVERY_KEY")"

# ENGINE is unquoted on purpose: it may be a command with arguments, e.g. "sudo podman".
$ENGINE run --rm --privileged \
  -v /dev:/dev \
  -v "$(realpath "$archive"):/image.tar:ro" \
  -v "$(realpath "$DISK"):/disk.raw" \
  -v "$(realpath "$(dirname "$RECOVERY_KEY")"):/out" \
  -v "$(realpath scripts/install.sh):/install.sh:ro" \
  -e DISK=/disk.raw -e RECOVERY_KEY="/out/$(basename "$RECOVERY_KEY")" -e OWNER="$(id -u):$(id -g)" \
  -e SOURCE_IMGREF=oci-archive:/image.tar -e IMAGE="$IMAGE" \
  "$IMAGE" \
  /install.sh
