# ShapeBit OS image: agent and contributor rules

- **Verify with `make test`.** A change is done only when it passes. Add
  `ENGINE=docker` on hosts without Podman.
- **Prefer built-in tools.** Use what bootc, systemd, the Fedora base image, or
  QEMU already provide, such as `kargs.d`, systemd credentials, tmpfiles.d,
  sysusers.d, and presets. Add a package, script, or service only when nothing
  built in fits, and say why in a comment.
- **Make owns configuration.** Defaults live only in the `Makefile`. Scripts
  read them from the environment and fail fast on missing values
  (`: "${VAR:?}"`).
- **`rootfs/` mirrors the target filesystem.** Put vendor defaults under `/usr`.
  `/etc` and `/var` are machine state.
- **Every behavior gets a check.** Image content goes in `tests/image.sh`;
  runtime behavior goes in `tests/system.sh`. Use only tools the image ships.
  Only checks that need a host-side secret, such as the recovery key, go in
  `tests/boot.sh`.
- **Never put credentials in the image or disk.** Development access goes
  through systemd credentials at VM launch. Private signing keys reach builds
  only as build secrets; only signed binaries and public keys enter the image.
- **Keep shell scripts small.** Use Bash with `set -euo pipefail`, and start
  each script with a comment that says what it does and how to call it.
