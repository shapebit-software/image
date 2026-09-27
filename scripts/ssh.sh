#!/usr/bin/env bash
# Run ssh as root in the VM started by vm.sh; arguments are passed to ssh.
set -euo pipefail
: "${SSH_PORT:?}" "${SSH_KEY:?}"

# Each disk has new host keys, so they are never recorded.
exec ssh -i "$SSH_KEY" -p "$SSH_PORT" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o ConnectTimeout=5 \
  root@127.0.0.1 "$@"
