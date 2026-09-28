#!/usr/bin/env bash
# Enroll the VM's TPM2 in the LUKS2 volume of a newly installed DISK: the part
# of the installation that needs the machine's own TPM. Boots once, unlocked by
# RECOVERY_KEY, adds a key slot bound to PCR 7 and signed PCR 11, and powers off.
# Usage: enroll.sh (called by `make disk`).
set -euo pipefail
: "${RECOVERY_KEY:?}"
cd "$(dirname "$0")/.."

# systemd-boot enrolls the Secure Boot keys and reboots before SSH comes up,
# so PCR 7 already has its final value when the TPM is enrolled.
UNLOCK_KEY=$RECOVERY_KEY scripts/vm.sh --background
trap 'scripts/vm.sh --stop' EXIT

# The recovery key authorizes the new slot. It arrives on stdin, so it stays
# off command lines. The public key comes from the booted UKI.
scripts/ssh.sh 'PASSWORD=$(cat) systemd-cryptenroll \
  --tpm2-device=auto --tpm2-pcrs=7 \
  --tpm2-public-key=/run/systemd/tpm2-pcr-public-key.pem --tpm2-public-key-pcrs=11 \
  /dev/disk/by-partlabel/shapebit' <"$RECOVERY_KEY"
