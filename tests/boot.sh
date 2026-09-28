#!/usr/bin/env bash
# Boot DISK in the background, run tests/system.sh inside it, then power it off.
set -euo pipefail
: "${RECOVERY_KEY:?}"
cd "$(dirname "$0")/.."

# No UNLOCK_KEY: the disk must unlock with the TPM alone.
scripts/vm.sh --background
trap 'scripts/vm.sh --stop' EXIT

failed=0
scripts/ssh.sh bash -s <tests/system.sh || failed=1

# The recovery key lives only on the host, so this check runs from here.
if scripts/ssh.sh 'cryptsetup open --test-passphrase --key-file=- /dev/disk/by-partlabel/shapebit' <"$RECOVERY_KEY"; then
  echo "ok   recovery key unlocks the volume"
else
  echo "FAIL recovery key unlocks the volume"
  failed=1
fi

exit "$failed"
