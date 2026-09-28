#!/usr/bin/env bash
# Update an installed system and roll it back: boot DISK once (its first boot),
# build and publish IMAGE_VERSION.next, upgrade to it with bootc, run
# tests/system.sh on it, then roll back. Leaves IMAGE and BUILD/image.tar at
# the new build.
# Usage: update.sh (called by `make test-update`).
set -euo pipefail
: "${IMAGE_VERSION:?}"
cd "$(dirname "$0")/.."

next=$IMAGE_VERSION.next
failed=0
reboot() { scripts/vm.sh --stop && scripts/vm.sh --background; }
expect_version() {
  if [[ $(scripts/ssh.sh '. /etc/os-release && echo "$IMAGE_VERSION"') == "$1" ]]; then
    echo "ok   $2"
  else
    echo "FAIL $2"
    failed=1
  fi
}
trap 'scripts/vm.sh --stop' EXIT

scripts/vm.sh --background
scripts/ssh.sh systemctl is-system-running --wait >/dev/null || true
scripts/vm.sh --stop

IMAGE_VERSION=$next scripts/image.sh
scripts/publish.sh

scripts/vm.sh --background
scripts/ssh.sh bootc upgrade --quiet
reboot
expect_version "$next" "upgrade boots the new build"
scripts/ssh.sh bash -s <tests/system.sh || failed=1

scripts/ssh.sh bootc rollback
reboot
expect_version "$IMAGE_VERSION" "rollback boots the previous build"

exit "$failed"
