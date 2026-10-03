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
`tpm2-firstboot.service`, which runs only on the first boot (systemd's
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

## Real hardware

A disk image can run on an x86-64 UEFI machine with a TPM 2.0. Legacy (CSM)
boot must be off. This is a developer trial: every key is a development key.

1. Build a disk that has never booted. A booted one has already used its
   clear key and enrolled the VM's TPM. With `DISK_SIZE` equal to
   `IMAGE_SIZE`, there is no padding to write:

   ```bash
   make disk ENGINE=docker DISK_SIZE=12G
   ```

   Keep `build/recovery-key`: it is the only way in if the TPM refuses.
2. Write it to a disk or USB drive of at least 16 GB. This erases the target;
   check its name with `lsblk` first:

   ```bash
   sudo dd if=build/disk.raw of=/dev/sdX bs=4M conv=fsync status=progress
   ```

3. Choose the firmware setup:
   - **Secure Boot off.** The simplest trial; everything else is the same.
   - **Secure Boot in setup mode** (clear or reset the keys in the firmware
     setup), for the full chain. On the first power-on, hold Space to open
     the systemd-boot menu and choose **Enroll Secure Boot keys: auto**
     before anything else boots; systemd-boot enrolls automatically only in
     VMs. If the system boots first, its TPM slot binds to setup mode, and
     enrolling the keys later needs the recovery key. The development keys
     replace the manufacturer's, so add-in cards whose firmware Microsoft
     signed, such as discrete GPUs, may not start; the firmware setup can
     restore the factory keys.
4. Boot from it. The first boot unlocks without a prompt, grows the root,
   enrolls the machine's TPM, and asks on the screen for the first owner: a
   user name and a password. That user administers the machine (`sudo`).
5. Reboot once. The disk now unlocks with the TPM, and the root fills the
   disk.
6. Log in, connect to the network (`nmcli device wifi connect NAME --ask` for
   Wi-Fi), and run the system checks:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/shapebit-software/image/main/tests/system.sh |
     sudo OWNER_NAME="$USER" bash
   ```

If something fails, `journalctl -b -1` shows the first boot, and
`journalctl -b -1 -u tpm2-firstboot.service -u systemd-repart.service` its
first-boot steps.

The first owner's home takes most of the free space, as systemd-homed sizes
it by default until the home storage policy exists; that can leave too little
room for updates.

## Development access

The image and disk contain no credentials. `make vm` and `make test` generate
an SSH key in `build/ssh/` and pass its public key to the VM as the systemd
credential `ssh.authorized_keys.root`. They also pass the first owner,
`OWNER_NAME` (default `dev`) with the password in `build/owner-password`, as
a `home.create.*` credential, so the first boot creates that user instead of
asking on the console. There is no root password.

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
