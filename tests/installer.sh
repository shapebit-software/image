#!/usr/bin/env bash
# Checks run inside the booted installer medium, before it installs
# (`make disk`); uses only tools the medium ships. The VM attaches the medium
# with the serial "medium" and the target disk with the serial "target".
set -uo pipefail

failed=0
check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failed=1; fi
}

# Fedora 44's SELinux policy does not yet let systemd-tpm2-setup save its
# NvPCR anchor credential to the EFI System Partition, so that unit fails on
# the medium, which is the first system to start on a machine's TPM.
booted() {
  systemctl is-system-running --wait >/dev/null
  ! systemctl --failed --no-legend --plain | grep -qv '^systemd-tpm2-setup\.service '
}
check "medium finished booting without other failed units" booted
check "booted from a UKI" test -e /sys/firmware/efi/efivars/StubInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
check "Secure Boot is enabled" sh -c "mokutil --sb-state | grep -q 'SecureBoot enabled'"
check "medium is sealed by a composefs digest" grep -Eq '(^| )composefs=[0-9a-f]{128}( |$)' /proc/cmdline
check "payload is on the medium" test -s /usr/share/installer/image.tar
check "installer backend is running" systemctl -q is-active installer-backend.service
check "installer UI is running" systemctl -q is-active installer.service
ui_is_unprivileged() { test "$(ps -o user= -C installer | sort -u)" = installer; }
check "installer UI runs as an unprivileged user" ui_is_unprivileged
capable() { installerctl capabilities | grep -q '"tpm2":true.*"uefi":true'; }
check "backend finds UEFI and a TPM2" capable
offers_locales() { installerctl capabilities | grep -q '"locales":\[.*"en_US.UTF-8"'; }
check "backend offers the locales of the system" offers_locales
target_is_eligible() { installerctl disks | grep '"id":"serial-target"' | grep -q '"eligible":true'; }
check "target disk is eligible" target_is_eligible
medium_is_refused() { installerctl disks | grep '"id":"serial-medium"' | grep -q '"eligible":false'; }
check "medium itself is not eligible" medium_is_refused
unprivileged_is_refused() { ! setpriv --reuid nobody --regid nobody --clear-groups installerctl disks >/dev/null 2>&1; }
check "other users cannot reach the backend" unprivileged_is_refused

exit "$failed"
