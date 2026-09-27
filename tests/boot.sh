#!/usr/bin/env bash
# Boot DISK in the background, run tests/system.sh inside it, then stop the VM.
set -euo pipefail
: "${BUILD:?}"

BOOT_TIMEOUT=${BOOT_TIMEOUT:-300}
cd "$(dirname "$0")/.."

scripts/vm.sh --background
trap 'kill "$(cat "$BUILD/vm.pid")" 2>/dev/null || true' EXIT

echo "Waiting up to ${BOOT_TIMEOUT}s for SSH (console: $BUILD/serial.log)"
deadline=$((SECONDS + BOOT_TIMEOUT))
until scripts/ssh.sh true 2>/dev/null; do
  if ((SECONDS >= deadline)); then
    echo "error: no SSH after ${BOOT_TIMEOUT}s; last console lines:" >&2
    tail -n 30 "$BUILD/serial.log" >&2
    exit 1
  fi
  sleep 5
done

scripts/ssh.sh bash -s < tests/system.sh
