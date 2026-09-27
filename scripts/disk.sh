#!/usr/bin/env bash
# Install IMAGE to the raw disk DISK, encrypted with the passphrase in LUKS_KEY.
# The storage layout and install run inside the image (scripts/install.sh).
set -euo pipefail
: "${ENGINE:?}" "${IMAGE:?}" "${BUILD:?}" "${DISK:?}" "${DISK_SIZE:?}" "${LUKS_KEY:?}"

archive=$BUILD/image.tar
trap 'rm -f "$archive"' EXIT

# bootc reads the image from an OCI archive, so it works with any engine's storage.
# Docker always saves OCI layout; Podman needs --format.
# ENGINE is unquoted on purpose: it may be a command with arguments, e.g. "sudo podman".
save_args=()
if $ENGINE save --help | grep -q -- --format; then
  save_args=(--format oci-archive)
fi
mkdir -p "$BUILD"
$ENGINE save "${save_args[@]}" -o "$archive" "$IMAGE"

rm -f "$DISK"
truncate -s "$DISK_SIZE" "$DISK"

$ENGINE run --rm --privileged \
  -v /dev:/dev \
  -v "$(realpath "$archive"):/image.tar:ro" \
  -v "$(realpath "$DISK"):/disk.raw" \
  -v "$(realpath "$LUKS_KEY"):/luks.key:ro" \
  -v "$(realpath scripts/install.sh):/install.sh:ro" \
  -e DISK=/disk.raw -e LUKS_KEY=/luks.key \
  -e SOURCE_IMGREF=oci-archive:/image.tar -e IMAGE="$IMAGE" \
  "$IMAGE" \
  /install.sh
