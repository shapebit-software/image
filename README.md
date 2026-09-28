# ShapeBit OS image

The bootable ShapeBit OS image: a [bootc](https://bootc-dev.github.io/bootc/)
container built on Fedora bootc 44, installed to a disk that follows the
[Base System](https://shapebit.software/docs/) architecture. It is currently
console-only.

## Requirements

A Linux x86-64 host with KVM, a container engine, QEMU, Secure Boot capable
UEFI firmware, a software TPM, OpenSSH, and OpenSSL:

```bash
sudo dnf install podman make qemu-kvm edk2-ovmf swtpm openssh-clients openssl   # Fedora
sudo apt install podman make qemu-system-x86 ovmf swtpm openssh-client openssl  # Debian/Ubuntu
```

The default engine is `sudo podman`, because installing to a disk needs root.
To use Docker instead, add `ENGINE=docker` to any command.

## Usage

```bash
make test    # build, check, install, enroll the TPM, boot, and check the running system
make vm      # boot build/disk.raw with the serial console on this terminal
make ssh     # root shell in the running VM (from another terminal)
make clean   # remove build/, including the disk, keys, and recovery key
make help    # all targets
```

Settings are variables at the top of the [Makefile](Makefile), such as
`IMAGE`, `DISK_SIZE`, and `SSH_PORT`.

## How it works

### Build

`make image` ([scripts/image.sh](scripts/image.sh)) builds in two phases. It
signs with development keys that [scripts/keys.sh](scripts/keys.sh) generates
in `build/keys/`: Secure Boot PK, KEK, and db, and a TPM2 PCR policy key.

1. [Containerfile](Containerfile) builds the system: systemd-boot signed with
   db, the Secure Boot public keys, and systemd-homed login support.
2. [Containerfile.seal](Containerfile.seal) adds a UKI signed with db. Its
   command line pins the system's composefs digest, and it carries signed
   PCR 11 values for TPM2 unlock. The digest is computed from the built
   image, as `bootc install` computes it.

The sealed image is saved as `build/image.tar`.

### Disk

`make disk` installs in two steps:

1. [scripts/install.sh](scripts/install.sh) lays out the disk inside the image
   container and installs with bootc's composefs backend. The volume gets a
   recovery key, saved to `build/recovery-key`.
2. [scripts/enroll.sh](scripts/enroll.sh) boots the VM once, unlocked by the
   recovery key, and enrolls the VM's TPM.

| Partition  | Content                                                        |
| ---------- | -------------------------------------------------------------- |
| `esp`      | EFI System Partition: systemd-boot, UKIs, Secure Boot keys.    |
| `shapebit` | LUKS2 volume with one Btrfs filesystem, split into subvolumes. |

| Subvolume   | Mounted at  | Content                                             |
| ----------- | ----------- | --------------------------------------------------- |
| `@base`     | `/sysroot`  | composefs images and each deployment's `/etc`.      |
| `@machine`  | `/var`      | This device's state.                                |
| `@people`   | `/var/home` | systemd-homed homes (`/home` links to `/var/home`). |
| `@recovery` | not mounted | Reserved for recovery data.                         |

The LUKS2 partition has the x86-64 root partition type, so systemd finds and
unlocks it without machine-specific kernel arguments, which a UKI cannot carry.

### Boot and unlock

The VM firmware starts in setup mode, so on first boot systemd-boot enrolls the
image's Secure Boot keys and reboots. From then on the firmware runs only the
signed systemd-boot, which runs only the signed UKI, which mounts only the
system whose digest it pins. Development builds use no Microsoft-signed shim.

The LUKS2 volume has two key slots:

- **TPM2**, bound to PCR 7 (the Secure Boot policy) and to PCR 11 values
  signed by the PCR policy key. A new UKI signed with the same key unlocks
  without re-enrollment.
- **Recovery key**. If the TPM refuses, the console asks for a passphrase, and
  the recovery key works there.

The VM's EFI variables (`build/efivars.fd`) and TPM state (`build/tpm/`)
belong to the disk; `make disk` resets them.

### Homes

Users are [systemd-homed](https://systemd.io/HOME_DIRECTORY/) homes. Each home
is a LUKS2-encrypted image, `/home/<user>.home` in `@people`, with Btrfs
inside, unlocked by its owner's password at login.

## Development access

The image and disk contain no credentials. `make vm` and `make test` generate
an SSH key in `build/ssh/` and pass its public key to the VM as the systemd
credential `ssh.authorized_keys.root`. There is no password login and no user;
run `homectl create` in `make ssh` to add one.

## Layout

| Path                 | Purpose                                                     |
| -------------------- | ----------------------------------------------------------- |
| `Containerfile`      | The unsealed system.                                        |
| `Containerfile.seal` | Adds the signed UKI to the built system.                    |
| `rootfs/`            | Files copied verbatim into the image; paths mirror `/`.     |
| `scripts/`           | Keys, image build, disk install, TPM enrollment, QEMU, SSH. |
| `tests/`             | Checks for the image (`image.sh`) and the VM (`boot.sh`).   |
| `build/`             | Generated outputs (ignored by Git).                         |

## Not yet implemented

- A minimal signed recovery UKI.
- The home storage policy: guaranteed minimums, the machine reserve, and
  low-space states. systemd-homed's defaults size homes for now.
- A first owner; the installer creates it.
