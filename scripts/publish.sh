#!/usr/bin/env bash
# Push IMAGE to the local update registry, starting the registry if needed.
# Installed systems update from it as UPDATE_REF.
# Usage: publish.sh (called by `make publish`).
set -euo pipefail
: "${ENGINE:?}" "${IMAGE:?}" "${REGISTRY_PORT:?}" "${UPDATE_REF:?}"

# ENGINE is unquoted on purpose: it may be a command with arguments, e.g. "sudo podman".
name=dev-registry
if [[ -z $($ENGINE ps -q --filter "name=^$name\$") ]]; then
  $ENGINE rm -f "$name" >/dev/null 2>&1 || true
  $ENGINE run -d --name "$name" -p "127.0.0.1:$REGISTRY_PORT:5000" docker.io/library/registry:2 >/dev/null
fi

# The host reaches the registry at localhost; the path and tag match UPDATE_REF.
ref=localhost:$REGISTRY_PORT/${UPDATE_REF#*/}
push_args=()
if $ENGINE push --help | grep -q -- --tls-verify; then
  push_args=(--tls-verify=false)
fi
$ENGINE tag "$IMAGE" "$ref"
$ENGINE push "${push_args[@]}" "$ref"
