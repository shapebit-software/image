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
check "os-release identifies ShapeBit OS" test "$ID" = shapebit-os
check "default target is multi-user" test "$(systemctl get-default)" = multi-user.target
check "sshd is enabled" systemctl -q is-enabled sshd.service
check "NetworkManager is enabled" systemctl -q is-enabled NetworkManager.service
check "serial console karg is set" grep -q 'console=ttyS0' /usr/lib/bootc/kargs.d/10-console.toml

exit "$failed"
