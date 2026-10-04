#!/usr/bin/env bash
# Install ShapeBit to the raw disk DISK of DISK_SIZE the way a user does: boot
# the installer medium MEDIUM in QEMU with the empty disk attached, and let the
# installer install to it. Saves the recovery key to RECOVERY_KEY.
# Usage: disk.sh           check the medium (tests/installer.sh), then install
#                          through installerctl, without the UI
#        disk.sh --window  open the VM in a window, to install by hand
set -euo pipefail
: "${BUILD:?}" "${DISK:?}" "${DISK_SIZE:?}" "${MEDIUM:?}" "${RECOVERY_KEY:?}" "${OWNER_NAME:?}" "${OWNER_PASSWORD:?}" \
  "${LOCALE:?}" "${KEYBOARD_LAYOUT:?}" "${TIME_ZONE:?}"
cd "$(dirname "$0")/.."

[[ -f $MEDIUM ]] || { echo "error: $MEDIUM not found; run 'make installer'" >&2; exit 1; }

# A new disk is a new machine: fresh EFI variables and TPM (see vm.sh).
rm -rf "$DISK" "$RECOVERY_KEY" "$BUILD/efivars.fd" "$BUILD/tpm" "$BUILD/serial.log"
truncate -s "$DISK_SIZE" "$DISK"

if [[ ${1:-} == --window ]]; then
  exec scripts/vm.sh --installer --window
fi

trap 'scripts/vm.sh --stop' EXIT
scripts/vm.sh --installer --background
scripts/ssh.sh bash -s <tests/installer.sh

# The password and the recovery key stay in the VM's memory (/run). The small
# home leaves the disk to the system.
scripts/ssh.sh 'umask 077 && cat >/run/owner-password' <"$OWNER_PASSWORD"
scripts/ssh.sh installerctl install --disk serial-target --user "$OWNER_NAME" \
  --home-size $((1024 * 1024 * 1024)) \
  --locale "$LOCALE" --keyboard-layout "$KEYBOARD_LAYOUT" --time-zone "$TIME_ZONE" \
  --password-file /run/owner-password --recovery-key-file /run/recovery-key
(umask 077 && scripts/ssh.sh cat /run/recovery-key >"$RECOVERY_KEY")
