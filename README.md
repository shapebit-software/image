# ShapeBit OS image

The bootable ShapeBit OS image: a [bootc](https://bootc-dev.github.io/bootc/)
container built on Fedora bootc 44. It is currently console-only.

## Requirements

A Linux x86-64 host with KVM, a container engine, QEMU, UEFI firmware, and
OpenSSH:

```bash
sudo dnf install podman make qemu-kvm edk2-ovmf openssh-clients      # Fedora
sudo apt install podman make qemu-system-x86 ovmf openssh-client     # Debian/Ubuntu
```

The default engine is `sudo podman`, because installing to a disk needs root.
To use Docker instead, add `ENGINE=docker` to any command.

## Usage

```bash
make test    # build, check, install to a disk, boot it, and check the running system
make vm      # boot build/disk.raw with the serial console on this terminal
make ssh     # root shell in the running VM (from another terminal)
make help    # all targets
```

All settings are variables at the top of the [Makefile](Makefile), such as
`IMAGE`, `DISK_SIZE`, and `SSH_PORT`.

## Development access

The image and disk contain no credentials. `make vm` and `make test` generate a
key in `build/ssh/` and pass its public key to the VM as the systemd credential
`ssh.authorized_keys.root`. There is no password login.

## Layout

| Path            | Purpose                                                     |
| --------------- | ----------------------------------------------------------- |
| `Containerfile` | The image definition.                                       |
| `rootfs/`       | Files copied verbatim into the image; paths mirror `/`.     |
| `scripts/`      | Host helpers: disk install, QEMU launcher, SSH.             |
| `tests/`        | `image.sh` runs in the container, `system.sh` in the VM.    |
| `build/`        | Generated outputs (ignored by Git).                         |

## Not yet implemented

The development disk uses the default layout from `bootc install`: GRUB, an
unencrypted Btrfs root, and no TPM. It does not yet match the
[Base System](https://shapebit.software/docs/) architecture, which requires
LUKS2, `@base`/`@machine`/`@people`/`@recovery` subvolumes, systemd-boot with
signed UKIs, and `systemd-homed`.
