#!/usr/bin/env bash
# Build a bootable image in two phases: the unsealed system from CONTAINERFILE,
# then IMAGE, sealed with its signed UKI (Containerfile.seal). Saves the result
# as the OCI archive ARCHIVE, which bootc installs from.
# Usage: image.sh CONTAINERFILE IMAGE ARCHIVE [BUILD_OPTION...]
#        (called by `make image` and `make installer`; the build options go to
#        the first phase).
set -euo pipefail
: "${ENGINE:?}" "${BUILD:?}" "${KEYS_DIR:?}"
containerfile=$1 image=$2 archive=$3
shift 3

unsealed=$image-unsealed
unsealed_archive=$BUILD/unsealed.tar
trap 'rm -f "$unsealed_archive"' EXIT
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

$ENGINE build --build-arg KEYS_ID="$keys_id" "${secrets[@]}" "$@" -f "$containerfile" -t "$unsealed" .

# The digest comes from the image as `bootc install` reads it: imported into
# container storage (an anonymous volume) from an OCI archive.
save "$unsealed" "$unsealed_archive"
digest=$($ENGINE run --rm --privileged \
  -v "$(realpath "$unsealed_archive"):/image.tar:ro" \
  -v /var/lib/containers \
  "$unsealed" \
  bash -c 'skopeo copy -q oci-archive:/image.tar containers-storage:localhost/unsealed &&
           bootc container compute-composefs-digest-from-storage localhost/unsealed' |
  tail -n 1)
[[ $digest =~ ^[0-9a-f]{128}$ ]] || { echo "error: bad composefs digest: $digest" >&2; exit 1; }

$ENGINE build --build-arg UNSEALED="$unsealed" --build-arg COMPOSEFS_DIGEST="$digest" --build-arg KEYS_ID="$keys_id" \
  "${secrets[@]}" -f Containerfile.seal -t "$image" .
save "$image" "$archive"
