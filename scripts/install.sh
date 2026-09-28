#!/usr/bin/env bash
# Lay out the Base System storage on the raw disk DISK and install the image into it.
# Runs inside the privileged image container started by disk.sh; the image
# ships every tool used here.
set -euo pipefail
: "${DISK:?}" "${RECOVERY_KEY:?}" "${OWNER:?}" "${SOURCE_IMGREF:?}" "${IMAGE:?}"

# No udev in the container; device-mapper must not wait for it.
export DM_DISABLE_UDEV=1

mapper=install-root
install_key=/run/install/key
top=/run/install/top
target=/run/install/target

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

# A random installation key opens the volume during the install and is then
# replaced by two slots: a recovery key, saved to RECOVERY_KEY for the owner,
# and a clear key (an empty passphrase, so it needs no costly key derivation)
# that unlocks the first boot. There, tpm2-enroll.service replaces the
# clear key with the machine's TPM2.
mkdir -p "${install_key%/*}"
(umask 077 && head -c 64 /dev/urandom >"$install_key")
cryptsetup luksFormat --batch-mode --type luks2 --label shapebit --key-file "$install_key" "$luks"
cryptsetup open --key-file "$install_key" "$luks" "$mapper"
printf '\n' | cryptsetup luksAddKey --batch-mode --force-password \
  --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file "$install_key" "$luks"
systemd-cryptenroll --unlock-key-file="$install_key" --recovery-key --wipe-slot=0 "$luks" |
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
etc=$(echo "$target"/state/deploy/*/etc)
cat >>"$etc/fstab" <<EOF
UUID=$btrfs_uuid /var      btrfs subvol=@machine 0 0
UUID=$btrfs_uuid /var/home btrfs subvol=@people  0 0
EOF

# The image's empty machine-id makes systemd use a new, temporary ID at every
# boot. "uninitialized" marks the first boot instead: systemd generates the ID
# and saves it once that boot completes (ConditionFirstBoot, machine-id(5)).
echo uninitialized >"$etc/machine-id"

for mountpoint in "$target/boot" "$target"; do
  fstrim --quiet-unsupported "$mountpoint"
done
