#!/usr/bin/env bash
# Boot DISK in QEMU with UEFI firmware and SSH forwarded to 127.0.0.1:SSH_PORT.
# Usage: vm.sh              serial console on this terminal (Ctrl-A X quits)
#        vm.sh --background  detached; console in BUILD/serial.log, PID in BUILD/vm.pid
set -euo pipefail
: "${BUILD:?}" "${DISK:?}" "${SSH_PORT:?}" "${SSH_KEY:?}" "${LUKS_KEY:?}"

[[ -f $DISK ]] || { echo "error: $DISK not found; run 'make disk'" >&2; exit 1; }

# UEFI firmware locations (code:vars) on Fedora, Debian/Ubuntu, and Arch.
# Override with OVMF_CODE and OVMF_VARS.
if [[ -z ${OVMF_CODE:-} ]]; then
  for pair in \
    /usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd; do
    if [[ -f ${pair%%:*} ]]; then
      OVMF_CODE=${pair%%:*} OVMF_VARS=${pair##*:}
      break
    fi
  done
fi
[[ -n ${OVMF_CODE:-} ]] || { echo "error: OVMF firmware not found; set OVMF_CODE and OVMF_VARS" >&2; exit 1; }

# Each new disk starts with fresh EFI variables.
vars=$BUILD/efivars.fd
[[ $vars -nt $DISK ]] || cp "$OVMF_VARS" "$vars"

# The SSH key and the disk passphrase reach the guest as systemd credentials;
# nothing is baked into the disk. systemd-cryptsetup in the initrd reads
# cryptsetup.passphrase to unlock the LUKS2 volume.
key=$(base64 -w0 < "$SSH_KEY.pub")
passphrase=$(base64 -w0 < "$LUKS_KEY")

args=(
  -machine q35,accel=kvm -cpu host -m 4096 -smp 4
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,unit=1,file=$vars"
  -drive "if=virtio,format=raw,discard=unmap,file=$DISK"
  -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
  -smbios "type=11,value=io.systemd.credential.binary:ssh.authorized_keys.root=$key"
  -smbios "type=11,value=io.systemd.credential.binary:cryptsetup.passphrase=$passphrase"
)

if [[ ${1:-} == --background ]]; then
  exec qemu-system-x86_64 "${args[@]}" -display none \
    -serial "file:$BUILD/serial.log" -daemonize -pidfile "$BUILD/vm.pid"
fi
exec qemu-system-x86_64 "${args[@]}" -nographic
