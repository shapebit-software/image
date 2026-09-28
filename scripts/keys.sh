#!/usr/bin/env bash
# Generate development signing keys in KEYS_DIR: Secure Boot PK, KEK, and db
# (.key and .crt), and the TPM2 PCR policy key that signs the UKI's expected
# PCR 11 values (tpm2-pcr-private.pem, tpm2-pcr-public.pem).
# Usage: keys.sh (called by `make`; existing keys are kept).
set -euo pipefail
: "${KEYS_DIR:?}"

mkdir -p "$KEYS_DIR"
for name in PK KEK db; do
  [[ -f $KEYS_DIR/$name.crt ]] && continue
  openssl req -quiet -new -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -subj "/CN=ShapeBit development $name/" \
    -keyout "$KEYS_DIR/$name.key" -out "$KEYS_DIR/$name.crt"
done
if [[ ! -f $KEYS_DIR/tpm2-pcr-public.pem ]]; then
  openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$KEYS_DIR/tpm2-pcr-private.pem"
  openssl pkey -in "$KEYS_DIR/tpm2-pcr-private.pem" -pubout -out "$KEYS_DIR/tpm2-pcr-public.pem"
fi
