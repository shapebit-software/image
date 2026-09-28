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
make test         # build, check, install, boot twice, and check the running system
make test-update  # install, update to a new build, check it, and roll back
make vm           # boot build/disk.raw with the serial console on this terminal
make ssh          # root shell in the running VM (from another terminal)
make clean        # remove build/, including the disk, keys, and recovery key
make help         # all targets
```

Settings are variables at the top of the [Makefile](Makefile), such as
`IMAGE`, `IMAGE_VERSION`, `IMAGE_SIZE`, `DISK_SIZE`, and `SSH_PORT`.

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

`make disk` ([scripts/disk.sh](scripts/disk.sh)) installs the image to a raw
disk image of `IMAGE_SIZE`, then enlarges it to `DISK_SIZE`, as when the image
is written to a larger disk. [scripts/install.sh](scripts/install.sh) lays out
the disk inside the image container and installs with bootc's composefs
backend.

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

The LUKS2 volume holds these key slots:

| Key slot     | Added by                                    | Removed by     |
| ------------ | ------------------------------------------- | -------------- |
| Recovery key | `install.sh`, saved to `build/recovery-key` | never          |
| Clear key    | `install.sh`: an empty passphrase           | the first boot |
| TPM2         | the first boot                              | never          |

On the first boot the clear key unlocks the volume without a prompt, and
`tpm2-enroll.service`, which runs only on the first boot (systemd's
`ConditionFirstBoot`), replaces it with a TPM2 slot bound to PCR 7 (the
Secure Boot policy) and to PCR 11 values signed by the PCR policy key. A new
UKI signed with the same key unlocks without re-enrollment. Until that first
boot, anyone with the disk can unlock it. If the TPM ever refuses, the console
asks for a passphrase, and the recovery key works there.

`install.sh` marks the machine ID `uninitialized`, so the first boot generates
it and saves it once that boot completes. An interrupted first boot is
retried on the next boot.

The first boot also grows the root partition into free space (systemd-repart);
the next boot unlocks the larger LUKS2 volume and grows Btrfs (systemd-growfs).

The VM's EFI variables (`build/efivars.fd`) and TPM state (`build/tpm/`)
belong to the disk; `make disk` resets them.

### Updates

Each build records `IMAGE_VERSION` in `/usr/lib/os-release`. `make publish`
([scripts/publish.sh](scripts/publish.sh)) pushes the image to a local
registry container on the host, and installed systems update from it as
`UPDATE_REF`: the VM reaches the host at `10.0.2.2`, and `install.sh` marks
that plain-HTTP registry as insecure.

On the VM, `bootc upgrade` stages the new build, which boots after a restart;
`bootc rollback` returns to the previous one. The TPM unlocks the new build
without re-enrollment, because its UKI carries PCR 11 values signed by the
same key, and each deployment's `/etc` carries the machine's own changes.
[tests/update.sh](tests/update.sh) checks all of this.

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

| Path                 | Purpose                                                            |
| -------------------- | ------------------------------------------------------------------ |
| `Containerfile`      | The unsealed system.                                               |
| `Containerfile.seal` | Adds the signed UKI to the built system.                           |
| `rootfs/`            | Files copied verbatim into the image; paths mirror `/`.            |
| `scripts/`           | Keys, image build, publishing, disk install, QEMU, SSH.            |
| `tests/`             | Checks: image (`image.sh`), VM (`boot.sh`), updates (`update.sh`). |
| `build/`             | Generated outputs (ignored by Git).                                |

## Installer

The installer will do the same on the target machine, where it knows the disk
and can use the TPM: it sizes the partition to the disk and enrolls the TPM
during installation, so the first-boot steps find nothing to do. What it
configures maps to built-in mechanisms that the development tooling can pass as
systemd credentials:

| Setting                               | Mechanism                                             |
| ------------------------------------- | ----------------------------------------------------- |
| Target disk                           | The disk layout in `install.sh`                       |
| TPM2 use, recovery key                | `systemd-cryptenroll`                                 |
| Locale, keyboard, time zone, hostname | `systemd-firstboot` or `firstboot.*` credentials      |
| First owner                           | `homectl create` or a `home.create.<user>` credential |
| Wi-Fi profile                         | A NetworkManager keyfile                              |
| Update source                         | `bootc install --target-imgref`                       |

## Not yet implemented

- Trial boots with automatic rollback (systemd's Automatic Boot Assessment)
  and the boot health check. They wait on upstream: bootc's composefs backend
  does not yet add boot counters to its entries (planned through
  `/etc/kernel/tries`), and Fedora 44's SELinux policy does not yet let
  `systemd-bless-boot` rename entries on the ESP.
- A minimal signed recovery UKI.
- The home storage policy: guaranteed minimums, the machine reserve, and
  low-space states. systemd-homed's defaults size homes for now.
- A first owner; the installer creates it.
