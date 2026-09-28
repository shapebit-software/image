#!/usr/bin/env bash
# Boot DISK in QEMU with Secure Boot firmware, a software TPM, and SSH
# forwarded to 127.0.0.1:SSH_PORT.
# Usage: vm.sh               serial console on this terminal (Ctrl-A X quits)
#        vm.sh --background  detached; returns once SSH is up. Console in
#                            BUILD/serial.log, PID in BUILD/vm.pid.
#        vm.sh --stop        power off the detached VM, so its writes reach the disk
# With UNLOCK_KEY set to a key file, the disk is unlocked with it instead of
# the TPM (enroll.sh uses this before the TPM is enrolled).
set -euo pipefail
: "${BUILD:?}" "${DISK:?}" "${SSH_PORT:?}" "${SSH_KEY:?}" "${BOOT_TIMEOUT:?}"

[[ -f $DISK ]] || { echo "error: $DISK not found; run 'make disk'" >&2; exit 1; }
cd "$(dirname "$0")/.."

if [[ ${1:-} == --stop ]]; then
  pid=$(cat "$BUILD/vm.pid" 2>/dev/null) || exit 0
  # A stale PID file must not stop an unrelated process.
  grep -qs qemu "/proc/$pid/cmdline" || exit 0
  scripts/ssh.sh systemctl poweroff 2>/dev/null || true
  for _ in {1..60}; do
    kill -0 "$pid" 2>/dev/null || exit 0
    sleep 1
  done
  echo "warning: VM did not power off; killing it" >&2
  kill "$pid" 2>/dev/null || true
  exit 0
fi

# Secure Boot capable UEFI firmware (code:vars) on Fedora, Debian/Ubuntu, and
# Arch. The vars start empty, so the firmware is in setup mode and systemd-boot
# enrolls the image's keys on first boot. Override with OVMF_CODE and OVMF_VARS.
if [[ -z ${OVMF_CODE:-} ]]; then
  for pair in \
    /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/OVMF/OVMF_CODE_4M.secboot.fd:/usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd; do
    if [[ -f ${pair%%:*} ]]; then
      OVMF_CODE=${pair%%:*} OVMF_VARS=${pair##*:}
      break
    fi
  done
fi
[[ -n ${OVMF_CODE:-} ]] || { echo "error: OVMF firmware not found; set OVMF_CODE and OVMF_VARS" >&2; exit 1; }

# The EFI variables and the TPM state belong to the machine; disk.sh removes
# both when it installs a new disk.
vars=$BUILD/efivars.fd
[[ -f $vars ]] || cp "$OVMF_VARS" "$vars"
tpm=$BUILD/tpm
mkdir -p "$tpm"
rm -f "$tpm/swtpm.sock"
swtpm socket --tpm2 --tpmstate dir="$tpm" --ctrl type=unixio,path="$tpm/swtpm.sock" \
  --terminate --daemon

# Development access reaches the guest as systemd credentials; nothing is
# baked into the disk.
args=(
  -machine q35,smm=on,accel=kvm -cpu host -m 4096 -smp 4
  -global driver=cfi.pflash01,property=secure,value=on
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,unit=1,file=$vars"
  -drive "if=virtio,format=raw,discard=unmap,file=$DISK"
  -chardev "socket,id=tpm,path=$tpm/swtpm.sock"
  -tpmdev emulator,id=tpm,chardev=tpm
  -device tpm-crb,tpmdev=tpm
  -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
  -smbios "type=11,value=io.systemd.credential.binary:ssh.authorized_keys.root=$(base64 -w0 <"$SSH_KEY.pub")"
)
# systemd-cryptsetup in the initrd reads cryptsetup.passphrase.
if [[ -n ${UNLOCK_KEY:-} ]]; then
  args+=(-smbios "type=11,value=io.systemd.credential.binary:cryptsetup.passphrase=$(base64 -w0 <"$UNLOCK_KEY")")
fi

if [[ ${1:-} != --background ]]; then
  exec qemu-system-x86_64 "${args[@]}" -nographic
fi

qemu-system-x86_64 "${args[@]}" -display none \
  -serial "file:$BUILD/serial.log" -daemonize -pidfile "$BUILD/vm.pid"
echo "Waiting up to ${BOOT_TIMEOUT}s for SSH (console: $BUILD/serial.log)"
deadline=$((SECONDS + BOOT_TIMEOUT))
until scripts/ssh.sh true 2>/dev/null; do
  if ((SECONDS >= deadline)); then
    echo "error: no SSH after ${BOOT_TIMEOUT}s; last console lines:" >&2
    tail -n 30 "$BUILD/serial.log" >&2
    kill "$(cat "$BUILD/vm.pid")"
    exit 1
  fi
  sleep 5
done
