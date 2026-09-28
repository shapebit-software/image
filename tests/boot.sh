#!/usr/bin/env bash
# Boot DISK twice and check the second boot: the first boot grows the root and
# replaces the clear key with the TPM, so the second must unlock with the TPM
# alone. Runs tests/system.sh inside the VM, then powers it off.
set -euo pipefail
: "${RECOVERY_KEY:?}"
cd "$(dirname "$0")/.."

trap 'scripts/vm.sh --stop' EXIT
scripts/vm.sh --background
scripts/ssh.sh systemctl is-system-running --wait >/dev/null || true
scripts/vm.sh --stop
scripts/vm.sh --background

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
