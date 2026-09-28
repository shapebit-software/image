#!/usr/bin/env bash
# Checks run inside the booted system (`make test`); uses only tools the image ships.
set -uo pipefail

failed=0
check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failed=1; fi
}

if ! check "system finished booting without failed units" systemctl is-system-running --wait; then
  systemctl --failed --no-legend
fi

. /etc/os-release
check "os-release identifies ShapeBit OS" test "$ID" = shapebit
booted_by_bootc() { bootc status --format=json | jq -e '.status.booted != null' >/dev/null; }
check "booted by bootc" booted_by_bootc
check "Secure Boot is enabled" sh -c "mokutil --sb-state | grep -q 'SecureBoot enabled'"
booted_by_systemd_boot() { bootctl status 2>/dev/null | grep -Eq '^ +Product: systemd-boot '; }
check "booted by systemd-boot" booted_by_systemd_boot
check "booted from a UKI" test -e /sys/firmware/efi/efivars/StubInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
check "root is sealed by a composefs digest" grep -Eq '(^| )composefs=[0-9a-f]{128}( |$)' /proc/cmdline
check "root filesystem is Btrfs" test "$(findmnt -no FSTYPE /sysroot)" = btrfs
check "root filesystem is on the LUKS2 volume" test "$(findmnt -nvo SOURCE /sysroot)" = /dev/mapper/root
is_luks2() { cryptsetup status root | grep -Eq '^ +type: +LUKS2$'; }
check "root volume is LUKS2" is_luks2
luks_dump() { cryptsetup luksDump --dump-json-metadata /dev/disk/by-partlabel/shapebit; }
tpm2_policy() {
  luks_dump | jq -e '[.tokens[] | select(.type == "systemd-tpm2")] | length == 1 and
    (.[0]["tpm2-pcrs"] == [7]) and (.[0]["tpm2_pubkey_pcrs"] == [11])' >/dev/null
}
check "TPM2 key slot is bound to PCR 7 and signed PCR 11" tpm2_policy
has_recovery_key() { luks_dump | jq -e '[.tokens[] | select(.type == "systemd-recovery")] | length == 1' >/dev/null; }
check "recovery key is enrolled" has_recovery_key
only_tpm2_and_recovery() { luks_dump | jq -e '.keyslots | length == 2' >/dev/null; }
check "no other key slots" only_tpm2_and_recovery
check "unlocked without a passphrase" test ! -e /run/credentials/@system/cryptsetup.passphrase
check "@base is mounted at /sysroot" test "$(findmnt -no FSROOT /sysroot)" = /@base
check "@machine is mounted at /var" test "$(findmnt -no FSROOT /var)" = /@machine
check "@people is mounted at /var/home" test "$(findmnt -no FSROOT /var/home)" = /@people
has_recovery() { btrfs subvolume list /sysroot | grep -Eq ' path @recovery$'; }
check "@recovery subvolume exists" has_recovery
check "serial console karg is active" grep -q 'console=ttyS0' /proc/cmdline

# A throwaway systemd-homed user shows that homes are encrypted images in @people.
# It is small, since the test is about where homes live, not how big they get.
user=shapebit-test
password=$(head -c 24 /dev/urandom | base64)
check "homed creates a home" env NEWPASSWORD="$password" homectl create "$user" --disk-size=512M
home_binding() { homectl inspect -j "$user" | jq -e --arg image "/home/$user.home" \
  '[.binding[]] | length == 1 and .[0].storage == "luks" and .[0].imagePath == $image' >/dev/null; }
check "home is a LUKS2 image in /home" home_binding
check "home image is in @people" test "$(findmnt -no FSROOT -T "/var/home/$user.home")" = /@people
home_resolves() { getent passwd "$user" >/dev/null; }
check "home user resolves through NSS" home_resolves
check "home activates with its password" env PASSWORD="$password" homectl activate "$user"
home_mounted() { [[ $(findmnt -no FSTYPE,SOURCE "/home/$user") =~ ^btrfs\ /dev/mapper/home- ]]; }
check "active home is Btrfs on dm-crypt" home_mounted
homectl deactivate "$user"
check "homed removes the home" homectl remove "$user"

exit "$failed"
