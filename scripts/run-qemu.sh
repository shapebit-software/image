#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require qemu-system-x86_64
DISK=${1:-build/shapebit-os.qcow2}
[[ -f "$DISK" ]] || die "Disk image not found: $DISK"

OVMF_CODE=${OVMF_CODE:-/usr/share/edk2/ovmf/OVMF_CODE.fd}
if [[ ! -f "$OVMF_CODE" ]]; then
  for candidate in /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
    [[ -f "$candidate" ]] && OVMF_CODE=$candidate && break
  done
fi
[[ -f "$OVMF_CODE" ]] || die "OVMF firmware not found; set OVMF_CODE"

exec qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -m 4096 \
  -smp 4 \
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive "file=$DISK,format=qcow2,if=virtio" \
  -device virtio-net-pci,netdev=n0 \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -nographic
