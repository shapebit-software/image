#!/usr/bin/env bash
# Install IMAGE to the raw disk DISK with the bootc shipped inside the image.
set -euo pipefail
: "${ENGINE:?}" "${IMAGE:?}" "${BUILD:?}" "${DISK:?}" "${DISK_SIZE:?}"

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
  "$IMAGE" \
  bootc install to-disk \
    --via-loopback \
    --generic-image \
    --filesystem btrfs \
    --source-imgref oci-archive:/image.tar \
    --target-imgref "$IMAGE" \
    --skip-fetch-check \
    /disk.raw
