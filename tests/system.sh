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
check "os-release identifies ShapeBit OS" test "$ID" = shapebit-os
booted_by_bootc() { bootc status --format=json | jq -e '.status.booted != null' >/dev/null; }
check "booted by bootc" booted_by_bootc
check "root filesystem is Btrfs" test "$(findmnt -no FSTYPE /sysroot)" = btrfs
check "serial console karg is active" grep -q 'console=ttyS0' /proc/cmdline

exit "$failed"
