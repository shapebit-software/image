#!/usr/bin/env bash
# Checks run inside the container image (`make check`); uses only tools the image ships.
set -uo pipefail

failed=0
check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failed=1; fi
}

. /etc/os-release
check "os-release identifies ShapeBit OS" test "$ID" = shapebit
check "os-release carries the image version" test -n "${IMAGE_VERSION:-}"
check "default target is multi-user" test "$(systemctl get-default)" = multi-user.target
check "sshd is enabled" systemctl -q is-enabled sshd.service
check "NetworkManager is enabled" systemctl -q is-enabled NetworkManager.service
check "systemd-homed is enabled" systemctl -q is-enabled systemd-homed.service
check "first-owner prompt is enabled" systemctl -q is-enabled systemd-homed-firstboot.service
check "PAM uses systemd-homed" grep -q pam_systemd_home /etc/pam.d/system-auth
initramfs_skips_var() { lsinitrd /usr/lib/modules/*/initramfs.img -f usr/lib/composefs/setup-root-conf.toml | grep -q '^mount = "none"'; }
check "initramfs leaves /var to fstab" initramfs_skips_var
check "signed systemd-boot is present" test -s /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed
has_uki() { compgen -G '/boot/EFI/Linux/*.efi' >/dev/null; }
check "UKI is present" has_uki
uki_has_pcr_policy() { grep -aq '\.pcrsig' /boot/EFI/Linux/*.efi && grep -aq '\.pcrpkey' /boot/EFI/Linux/*.efi; }
check "UKI carries a signed PCR policy" uki_has_pcr_policy
has_sb_keys() { for key in PK KEK db; do test -s "/usr/lib/bootc/install/secureboot-keys/auto/$key.auth" || return 1; done; }
check "Secure Boot keys are present" has_sb_keys

exit "$failed"
