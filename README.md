# ShapeBit OS image

This repository contains the first console-only ShapeBit OS bootc image
scaffold. It currently targets Fedora bootc 44 and uses `multi-user.target`;
the custom desktop is outside this stage.

## Host requirements

Fedora is the preferred development host. The current workflow requires
Podman, Just, QEMU/KVM, and OVMF:

```bash
sudo dnf install podman just qemu-kvm edk2-ovmf
```

## Commands

Run commands from this repository's root:

```bash
just build    # build the bootc container image
just lint     # run bootc container lint
just test     # run container smoke tests
just disk     # create build/shapebit-os.qcow2
just run      # boot the disk in QEMU
```

`SHAPEBIT_OS_IMAGE` overrides the default image tag, and `SHAPEBIT_OS_DISK`
overrides the default disk path.

The development disk uses temporary credentials:

```text
login: shapebit
password: shapebit
SSH: localhost:2222
```

Never use these credentials in a distributable image.

This temporary account is created by the disk-image builder and does not yet
implement ShapeBit's accepted per-user `systemd-homed` encryption model.
The current disk script also does not yet implement TPM2-unlocked system-volume
encryption; its output is a development artifact, not the production security
layout.

## Current scope

- Fedora bootc 44 base image
- console login through `multi-user.target`
- NetworkManager and SSH
- ShapeBit branding and first-boot service
- container lint and smoke-test scripts
- QCOW2 generation and QEMU launcher

Successful end-to-end build and boot verification is tracked in the parent
repository's
[system design](https://github.com/shapebit-software/docs/wiki/system-design).
