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
check "root filesystem is Btrfs" test "$(findmnt -no FSTYPE /sysroot)" = btrfs
check "root filesystem is on the LUKS2 volume" test "$(findmnt -nvo SOURCE /sysroot)" = /dev/mapper/shapebit
is_luks2() { cryptsetup status shapebit | grep -Eq '^ +type: +LUKS2$'; }
check "shapebit volume is LUKS2" is_luks2
check "@base is mounted at /sysroot" test "$(findmnt -no FSROOT /sysroot)" = /@base
check "@machine is mounted at /var" test "$(findmnt -no FSROOT /var)" = /@machine
check "@people is mounted at /var/home" test "$(findmnt -no FSROOT /var/home)" = /@people
has_recovery() { btrfs subvolume list /sysroot | grep -Eq ' path @recovery$'; }
check "@recovery subvolume exists" has_recovery
check "serial console karg is active" grep -q 'console=ttyS0' /proc/cmdline

exit "$failed"
