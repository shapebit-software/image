#!/usr/bin/env bash
# Boot the installed DISK and check it: the installer enrolled the TPM, so the
# first boot must already unlock with the TPM alone. Runs tests/system.sh
# inside the VM, then powers it off.
set -euo pipefail
: "${RECOVERY_KEY:?}" "${OWNER_NAME:?}" "${LOCALE:?}" "${KEYBOARD_LAYOUT:?}" "${TIME_ZONE:?}"
cd "$(dirname "$0")/.."

trap 'scripts/vm.sh --stop' EXIT
scripts/vm.sh --background

failed=0
scripts/ssh.sh "OWNER_NAME=$OWNER_NAME LOCALE=$LOCALE KEYBOARD_LAYOUT=$KEYBOARD_LAYOUT TIME_ZONE=$TIME_ZONE bash -s" \
  <tests/system.sh || failed=1

# The recovery key lives only on the host, so this check runs from here.
if scripts/ssh.sh 'cryptsetup open --test-passphrase --key-file=- /dev/disk/by-partlabel/shapebit' <"$RECOVERY_KEY"; then
  echo "ok   recovery key unlocks the volume"
else
  echo "FAIL recovery key unlocks the volume"
  failed=1
fi

exit "$failed"
