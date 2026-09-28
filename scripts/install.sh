#!/usr/bin/env bash
# Lay out the Base System storage on the raw disk DISK and install the image into it.
# Runs inside the privileged image container started by disk.sh; the image
# ships every tool used here.
set -euo pipefail
: "${DISK:?}" "${RECOVERY_KEY:?}" "${OWNER:?}" "${SOURCE_IMGREF:?}" "${IMAGE:?}"

# No udev in the container; device-mapper must not wait for it.
export DM_DISABLE_UDEV=1

mapper=shapebit-install
install_key=/run/shapebit/install.key
top=/run/shapebit/top
target=/run/shapebit/target

loop=$(losetup --find --show --partscan "$DISK")
cleanup() {
  umount -R "$target" "$top" 2>/dev/null || true
  cryptsetup close "$mapper" 2>/dev/null || true
  losetup -d "$loop"
}
trap cleanup EXIT

# GPT: EFI System Partition and the LUKS2 volume, typed as the x86-64 root
# partition so that systemd finds and unlocks it without machine-specific kargs.
sfdisk --quiet --label gpt "$loop" <<'EOF'
size=1GiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=esp
           type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, name=shapebit
EOF
partx --update "$loop"
esp=${loop}p1 luks=${loop}p2

mkfs.vfat -F 32 -n ESP "$esp" >/dev/null

# A random installation key opens the volume once; it is then replaced by a
# recovery key, saved to RECOVERY_KEY for the owner. enroll.sh adds the TPM2
# key slot on the machine itself.
mkdir -p "${install_key%/*}"
(umask 077 && head -c 64 /dev/urandom >"$install_key")
cryptsetup luksFormat --batch-mode --type luks2 --label shapebit --key-file "$install_key" "$luks"
cryptsetup open --key-file "$install_key" "$luks" "$mapper"
systemd-cryptenroll --unlock-key-file="$install_key" --recovery-key --wipe-slot=password "$luks" |
  tr -d '\n' >"$RECOVERY_KEY"
chown "$OWNER" "$RECOVERY_KEY"
chmod 600 "$RECOVERY_KEY"
rm "$install_key"
mkfs.btrfs -q -L shapebit "/dev/mapper/$mapper"

mkdir -p "$top" "$target"
mount "/dev/mapper/$mapper" "$top"
for subvolume in @base @machine @people @recovery; do
  btrfs -q subvolume create "$top/$subvolume"
done

mount -o subvol=@base "/dev/mapper/$mapper" "$target"
mkdir "$target/boot"
mount "$esp" "$target/boot"

bootc install to-filesystem \
  --composefs-backend \
  --bootloader systemd \
  --generic-image \
  --skip-finalize \
  --source-imgref "$SOURCE_IMGREF" \
  --target-imgref "$IMAGE" \
  --skip-fetch-check \
  "$target"

# @machine holds /var and @people holds /home (/var/home). bootc filled the
# stateroot's /var; move it into @machine, then mount both from the
# deployment's /etc/fstab.
stateroot=$target/state/os/default
cp -a "$stateroot/var/." "$top/@machine/"
find "$stateroot/var" -mindepth 1 -delete
btrfs_uuid=$(blkid -s UUID -o value "/dev/mapper/$mapper")
deployments=("$target"/state/deploy/*)
cat >>"${deployments[0]}/etc/fstab" <<EOF
UUID=$btrfs_uuid /var      btrfs subvol=@machine 0 0
UUID=$btrfs_uuid /var/home btrfs subvol=@people  0 0
EOF

for mountpoint in "$target/boot" "$target"; do
  fstrim --quiet-unsupported "$mountpoint"
done
