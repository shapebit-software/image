#!/usr/bin/env bash
# Write the installer image archive (BUILD/installer.tar) to the raw disk
# MEDIUM of MEDIUM_SIZE: the installer medium, as it would be written to a USB
# drive. It is not encrypted and holds no secrets: an EFI System Partition and
# one Btrfs filesystem with the @base and @machine subvolumes. The layout and
# install run inside the image, which ships every tool used.
# Usage: medium.sh (called by `make installer`).
set -euo pipefail
: "${ENGINE:?}" "${INSTALLER_IMAGE:?}" "${BUILD:?}" "${MEDIUM:?}" "${MEDIUM_SIZE:?}"

archive=$BUILD/installer.tar
[[ -f $archive ]] || { echo "error: $archive not found; run 'make installer'" >&2; exit 1; }

rm -f "$MEDIUM"
truncate -s "$MEDIUM_SIZE" "$MEDIUM"

# ENGINE is unquoted on purpose: it may be a command with arguments, e.g. "sudo podman".
$ENGINE run --rm --privileged -i \
  -v /dev:/dev \
  -v "$(realpath "$archive"):/image.tar:ro" \
  -v "$(realpath "$MEDIUM"):/disk.raw" \
  "$INSTALLER_IMAGE" \
  bash -s <<'INSTALL'
set -euo pipefail
top=/run/medium/top
target=/run/medium/target

loop=$(losetup --find --show --partscan /disk.raw)
cleanup() {
  umount -R "$target" "$top" 2>/dev/null || true
  losetup -d "$loop"
}
trap cleanup EXIT

# The root has the x86-64 root partition type, so systemd finds it without
# machine-specific kernel arguments, as on an installed system.
sfdisk --quiet --label gpt "$loop" <<'LAYOUT'
size=1GiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=installer-esp
           type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, name=installer
LAYOUT
partx --update "$loop"
esp=${loop}p1 root=${loop}p2

mkfs.vfat -F 32 -n INSTALLER "$esp" >/dev/null
mkfs.btrfs -q -L installer "$root"

mkdir -p "$top" "$target"
mount "$root" "$top"
btrfs -q subvolume create "$top/@base"
btrfs -q subvolume create "$top/@machine"
mount -o subvol=@base "$root" "$target"
mkdir "$target/boot"
mount "$esp" "$target/boot"

bootc install to-filesystem \
  --composefs-backend \
  --bootloader systemd \
  --generic-image \
  --skip-finalize \
  --source-imgref oci-archive:/image.tar \
  --skip-fetch-check \
  "$target"

# @machine holds /var, as on an installed system: bootc filled the stateroot's
# /var; move it into @machine and mount it from the deployment's /etc/fstab.
stateroot=$target/state/os/default
cp -a "$stateroot/var/." "$top/@machine/"
find "$stateroot/var" -mindepth 1 -delete
etc=$(echo "$target"/state/deploy/*/etc)
echo "UUID=$(blkid -s UUID -o value "$root") /var btrfs subvol=@machine 0 0" >>"$etc/fstab"

# "uninitialized" marks the first boot: systemd generates the machine ID and
# saves it once that boot completes (machine-id(5)).
echo uninitialized >"$etc/machine-id"

for mountpoint in "$target/boot" "$target"; do
  fstrim --quiet-unsupported "$mountpoint"
done
INSTALL
