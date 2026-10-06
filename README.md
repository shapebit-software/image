# ShapeBit OS image

The bootable ShapeBit OS image: a [bootc](https://bootc-dev.github.io/bootc/)
container built on Fedora bootc 44, and the installer medium that installs it
to a disk that follows the [Base System](https://shapebit.software/docs/)
architecture. The system starts to a login screen; it has no desktop session
yet.

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

The installer source is expected next to this repository, in `../installer`
(`INSTALLER_SRC`), as in the ShapeBit OS monorepo.

```bash
make test          # build, check, install with the installer, boot, and check the running system
make test-update   # install, update to a new build, check it, and roll back
make installer-vm  # boot the installer medium in a window, to install by hand
make vm            # boot build/disk.raw with the serial console on this terminal
make ssh           # root shell in the running VM (from another terminal)
make clean         # remove build/, including the disks, keys, and recovery key
make help          # all targets
```

Settings are variables at the top of the [Makefile](Makefile), such as
`IMAGE`, `IMAGE_VERSION`, `DISK_SIZE`, `MEDIUM_SIZE`, and `SSH_PORT`.

## How it works

### Build

`make image` ([scripts/image.sh](scripts/image.sh)) builds in two phases. It
signs with development keys that [scripts/keys.sh](scripts/keys.sh) generates
in `build/keys/`: Secure Boot PK, KEK, and db, and a TPM2 PCR policy key.

1. [Containerfile](Containerfile) builds the system: systemd-boot signed with
   db, the Secure Boot public keys, systemd-homed login support, and the
   login screen.
2. [Containerfile.seal](Containerfile.seal) adds a UKI signed with db. Its
   command line pins the system's composefs digest, and it carries signed
   PCR 11 values for TPM2 unlock. The digest is computed from the built
   image, as `bootc install` computes it.

The sealed image is saved as `build/image.tar`.

### Installer medium

`make installer` builds the medium in the same two phases.
[Containerfile.installer](Containerfile.installer) adds, to the unsealed
system, the [installer](https://github.com/shapebit-software/installer), the
`cage` kiosk compositor that shows it, and the sealed system archive as the
payload; sealing then covers all of it with the medium's own signed UKI.
[scripts/medium.sh](scripts/medium.sh) writes the result to
`build/installer.raw`: an EFI System Partition and one unencrypted Btrfs
filesystem. The medium holds no secrets.

### Disk

`make disk` ([scripts/disk.sh](scripts/disk.sh)) installs the way a user does:
it boots the medium in QEMU with an empty disk of `DISK_SIZE` attached, checks
the medium ([tests/installer.sh](tests/installer.sh)), and runs the installer
through `installerctl`, the command-line client of the same D-Bus interface
that the UI uses. `make installer-vm` opens the same VM in a window instead.

The installer lays out the disk and installs with bootc's composefs backend.

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

The VM firmware starts in setup mode, so on its first boot the medium's
systemd-boot enrolls the image's Secure Boot keys and reboots. From then on
the firmware runs only the signed systemd-boot, which runs only the signed
UKI, which mounts only the system whose digest it pins. Development builds use
no Microsoft-signed shim.

The installer gives the LUKS2 volume two key slots:

| Key slot     | Purpose                                                  |
| ------------ | -------------------------------------------------------- |
| TPM2         | Unlocks every normal boot, without a prompt.             |
| Recovery key | Shown once by the installer; saved to `build/recovery-key` by `make disk`. |

The TPM2 slot is bound to PCR 7 (the Secure Boot policy) and to PCR 11 values
signed by the PCR policy key. The medium and the installed system are signed
with the same keys, so the slot that the installer enrolls unlocks the
installed system, and a new UKI signed with the same key unlocks without
re-enrollment. If the TPM ever refuses, the console asks for a passphrase, and
the recovery key works there. The random key that opens the volume during the
installation never leaves memory and is removed before the installer finishes.

The installer marks the machine ID `uninitialized`, so the first boot generates
it and saves it once that boot completes.

The VM's EFI variables (`build/efivars.fd`) and TPM state (`build/tpm/`)
belong to the machine, which the medium and the installed disk share;
`make disk` resets them.

### Updates

Each build records `IMAGE_VERSION` in `/usr/lib/os-release`. `make publish`
([scripts/publish.sh](scripts/publish.sh)) pushes the image to a local
registry container on the host, and installed systems update from it as
`UPDATE_REF`: the VM reaches the host at `10.0.2.2`, and the installer marks
that plain-HTTP registry as insecure.

On the VM, `bootc upgrade` stages the new build, which boots after a restart;
`bootc rollback` returns to the previous one. The TPM unlocks the new build
without re-enrollment, because its UKI carries PCR 11 values signed by the
same key, and each deployment's `/etc` carries the machine's own changes.
[tests/update.sh](tests/update.sh) checks all of this.

### Homes

Users are [systemd-homed](https://systemd.io/HOME_DIRECTORY/) homes. Each home
is a LUKS2-encrypted image, `/home/<user>.home` in `@people`, with Btrfs
inside, unlocked by its owner's password at login. The installer creates the
first owner, an administrator (`wheel`), directly on the installed disk.

### Login screen

[SDDM](https://github.com/sddm/sddm) shows the login screen on the first
virtual terminal; its greeter runs in Weston. The theme, in
[rootfs/usr/share/sddm/themes/login](rootfs/usr/share/sddm/themes/login), draws
the screen: the date and time, the accessibility and power menus, and the
person who signs in with their password. It lists systemd-homed users, uses
the Instrument Sans font (SIL Open Font License, in
[rootfs/usr/share/fonts/instrument-sans](rootfs/usr/share/fonts/instrument-sans),
since Fedora has no package of it), and draws its backdrop itself.

The image has no desktop session yet, so the login screen cannot start one
and says so. Consoles are on the other virtual terminals (Ctrl+Alt+F3). The
installer medium masks `sddm.service`, because the installer takes the screen
there.

To change the theme, run it in a window on a machine with SDDM:

```bash
sddm-greeter-qt6 --test-mode --theme rootfs/usr/share/sddm/themes/login
```

## Real hardware

The installer medium can install on an x86-64 UEFI machine with a TPM 2.0.
Legacy (CSM) boot must be off. This is a developer trial: every key is a
development key.

1. Build the medium:

   ```bash
   make installer ENGINE=docker
   ```

2. Write it to a USB drive of at least 16 GB. This erases the drive; check
   its name with `lsblk` first:

   ```bash
   sudo dd if=build/installer.raw of=/dev/sdX bs=4M conv=fsync status=progress
   ```

3. Choose the firmware setup before the first boot of the medium, because the
   installer binds the TPM to the Secure Boot state it finds:
   - **Secure Boot off.** The simplest trial; everything else is the same.
   - **Secure Boot in setup mode** (clear or reset the keys in the firmware
     setup), for the full chain. Hold Space while the medium starts, to open
     the systemd-boot menu, and choose **Enroll Secure Boot keys: auto**;
     systemd-boot enrolls automatically only in VMs. The development keys
     replace the manufacturer's, so add-in cards whose firmware Microsoft
     signed, such as discrete GPUs, may not start; the firmware setup can
     restore the factory keys.
4. Boot the medium and follow the installer: language, keyboard layout, time
   zone, account, and the disk, with the confirmation that erases it. The
   network step offers nothing yet; skip it. Write down the recovery key that it shows: it is the only way
   in if the TPM refuses.
5. Remove the medium and restart. The disk unlocks with the TPM.
6. Switch to a console (Ctrl+Alt+F3), log in, connect to the network
   (`nmcli device wifi connect NAME --ask` for Wi-Fi), and run the system
   checks:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/shapebit-software/image/main/tests/system.sh |
     sudo OWNER_NAME="$USER" bash
   ```

If something fails, `journalctl -b -u installer-backend.service` on the medium
shows the installation steps.

The first owner's home takes most of the free space, as systemd-homed sizes
it by default until the home storage policy exists; that can leave too little
room for updates.

## Development access

The images and disks contain no credentials. `make disk`, `make vm`, and
`make test` generate an SSH key in `build/ssh/` and pass its public key to the
VM as the systemd credential `ssh.authorized_keys.root`. `make disk` gives the
installer the first owner, `OWNER_NAME` (default `dev`) with the password in
`build/owner-password`, and the settings `LOCALE`, `KEYBOARD_LAYOUT`, and
`TIME_ZONE`. There is no root password.

## Layout

| Path                      | Purpose                                                             |
| ------------------------- | ------------------------------------------------------------------- |
| `Containerfile`           | The unsealed system.                                                |
| `Containerfile.installer` | The unsealed installer medium: the system, the installer, the payload. |
| `Containerfile.seal`      | Adds the signed UKI to an unsealed image.                           |
| `rootfs/`                 | Files copied verbatim into the image; paths mirror `/`.             |
| `scripts/`                | Keys, image build, medium, installation in QEMU, publishing, SSH.   |
| `tests/`                  | Checks: image (`image.sh`), medium (`installer.sh`), installed system (`boot.sh`, `system.sh`), updates (`update.sh`). |
| `build/`                  | Generated outputs (ignored by Git).                                 |

## Not yet implemented

- A desktop session for the login screen to start.
- Trial boots with automatic rollback (systemd's Automatic Boot Assessment)
  and the boot health check. They wait on upstream: bootc's composefs backend
  does not yet add boot counters to its entries (planned through
  `/etc/kernel/tries`), and Fedora 44's SELinux policy does not yet let
  `systemd-bless-boot` rename entries on the ESP.
- NvPCR measurements. The same policy does not let `systemd-tpm2-setup` save
  its anchor credential to the ESP, so that unit fails on the installer
  medium. The TPM2 unlock policy (PCR 7 and PCR 11) does not use NvPCRs.
- A minimal signed recovery UKI.
- The home storage policy: guaranteed minimums, the machine reserve, and
  low-space states. systemd-homed's defaults size homes for now.
