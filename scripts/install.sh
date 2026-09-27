#!/usr/bin/env bash
# Lay out the Base System storage on the raw disk DISK and install the image into it.
# Runs inside the privileged image container started by disk.sh; the image
# ships every tool used here.
set -euo pipefail
: "${DISK:?}" "${LUKS_KEY:?}" "${SOURCE_IMGREF:?}" "${IMAGE:?}"

# No udev in the container; device-mapper must not wait for it.
export DM_DISABLE_UDEV=1

mapper=shapebit-install
top=/run/shapebit/top
target=/run/shapebit/target

loop=$(losetup --find --show --partscan "$DISK")
cleanup() {
  umount -R "$target" "$top" 2>/dev/null || true
  cryptsetup close "$mapper" 2>/dev/null || true
  losetup -d "$loop"
}
trap cleanup EXIT

# GPT: EFI System Partition, the LUKS2 volume typed as the x86-64 root
# partition, and two temporary GRUB partitions: BIOS boot (bootupd installs
# every bootloader in a generic image) and /boot (GRUB cannot read LUKS2).
sfdisk --quiet --label gpt "$loop" <<'EOF'
size=1MiB,   type=21686148-6449-6E6F-744E-656564454649, name=bios
size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=esp
size=1GiB,   type=BC13C2FF-59E6-4262-A352-B275FD6F7172, name=boot
             type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, name=shapebit
EOF
partx --update "$loop"
esp=${loop}p2 boot=${loop}p3 luks=${loop}p4

mkfs.vfat -F 32 -n ESP "$esp" >/dev/null
mkfs.ext4 -q -L boot "$boot"
cryptsetup luksFormat --batch-mode --type luks2 --label shapebit --key-file "$LUKS_KEY" "$luks"
cryptsetup open --key-file "$LUKS_KEY" "$luks" "$mapper"
mkfs.btrfs -q -L shapebit "/dev/mapper/$mapper"

mkdir -p "$top" "$target"
mount "/dev/mapper/$mapper" "$top"
for subvolume in @base @machine @people @recovery; do
  btrfs -q subvolume create "$top/$subvolume"
done

mount -o subvol=@base "/dev/mapper/$mapper" "$target"
mkdir "$target/boot"
mount "$boot" "$target/boot"
mkdir "$target/boot/efi"
mount "$esp" "$target/boot/efi"

luks_uuid=$(cryptsetup luksUUID "$luks")
bootc install to-filesystem \
  --generic-image \
  --skip-finalize \
  --source-imgref "$SOURCE_IMGREF" \
  --target-imgref "$IMAGE" \
  --skip-fetch-check \
  --karg "rd.luks.name=$luks_uuid=shapebit" \
  "$target"

# @machine holds /var and @people holds /home (/var/home). bootc filled the
# stateroot's /var; move it into @machine, then mount both from /etc/fstab,
# which also stops OSTree from bind-mounting the stateroot /var.
stateroot=$target/ostree/deploy/default
cp -a "$stateroot/var/." "$top/@machine/"
find "$stateroot/var" -mindepth 1 -delete
btrfs_uuid=$(blkid -s UUID -o value "/dev/mapper/$mapper")
deployments=("$stateroot"/deploy/*.0)
cat >>"${deployments[0]}/etc/fstab" <<EOF
UUID=$btrfs_uuid /var      btrfs subvol=@machine 0 0
UUID=$btrfs_uuid /var/home btrfs subvol=@people  0 0
EOF

for mountpoint in "$target/boot/efi" "$target/boot" "$target"; do
  fstrim --quiet-unsupported "$mountpoint"
done
