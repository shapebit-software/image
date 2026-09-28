#!/usr/bin/env bash
# Build IMAGE in two phases: the unsealed system (Containerfile), then the
# sealed image with its signed UKI (Containerfile.seal). Saves the result as an
# OCI archive in BUILD/image.tar, which disk.sh installs.
# Usage: image.sh (called by `make image`).
set -euo pipefail
: "${ENGINE:?}" "${IMAGE:?}" "${FEDORA_VERSION:?}" "${BUILD:?}" "${KEYS_DIR:?}" "${IMAGE_VERSION:?}"

unsealed=$IMAGE-unsealed
archive=$BUILD/unsealed.tar
trap 'rm -f "$archive"' EXIT
mkdir -p "$BUILD"

# ENGINE is unquoted on purpose: it may be a command with arguments, e.g. "sudo podman".
# bootc reads images from OCI archives, so they work with any engine's storage.
# Docker always saves OCI layout; Podman needs --format.
save() {
  local args=()
  if $ENGINE save --help | grep -q -- --format; then
    args=(--format oci-archive)
  fi
  $ENGINE save "${args[@]}" -o "$2" "$1"
}

secrets=()
for key in PK.key PK.crt KEK.key KEK.crt db.key db.crt tpm2-pcr-private.pem tpm2-pcr-public.pem; do
  secrets+=(--secret "id=$key,src=$KEYS_DIR/$key")
done
# Build caches ignore secret contents; KEYS_ID makes signing steps rerun when
# the keys change.
keys_id=$(cat "$KEYS_DIR"/*.crt "$KEYS_DIR/tpm2-pcr-public.pem" | sha256sum | cut -d ' ' -f 1)

$ENGINE build --build-arg FEDORA_VERSION="$FEDORA_VERSION" --build-arg IMAGE_VERSION="$IMAGE_VERSION" \
  --build-arg KEYS_ID="$keys_id" "${secrets[@]}" \
  -f Containerfile -t "$unsealed" .

# The digest comes from the image as `bootc install` reads it: imported into
# container storage (an anonymous volume) from an OCI archive.
save "$unsealed" "$archive"
digest=$($ENGINE run --rm --privileged \
  -v "$(realpath "$archive"):/image.tar:ro" \
  -v /var/lib/containers \
  "$unsealed" \
  bash -c 'skopeo copy -q oci-archive:/image.tar containers-storage:localhost/unsealed &&
           bootc container compute-composefs-digest-from-storage localhost/unsealed' |
  tail -n 1)
[[ $digest =~ ^[0-9a-f]{128}$ ]] || { echo "error: bad composefs digest: $digest" >&2; exit 1; }

$ENGINE build --build-arg UNSEALED="$unsealed" --build-arg COMPOSEFS_DIGEST="$digest" --build-arg KEYS_ID="$keys_id" \
  "${secrets[@]}" -f Containerfile.seal -t "$IMAGE" .
save "$IMAGE" "$BUILD/image.tar"
