# ShapeBit OS Starter v0.1

The first ShapeBit OS scaffold: Fedora bootc, console-only, without GNOME, Weston, or a custom desktop environment.

## Host requirements

Fedora is the preferred development host.

```bash
sudo dnf install podman just qemu-kvm edk2-ovmf
```

## Build and run

```bash
just build
just test
just disk
just run
```

Default credentials for the development disk image:

```text
login: shapebit
password: shapebit
SSH: localhost:2222
```

This password is temporary and intended only for the development image.

## v0.1 scope

- Fedora bootc 44 base image;
- `multi-user.target`;
- NetworkManager and SSH;
- ShapeBit OS branding;
- smoke tests;
- QCOW2 generation;
- directory structure for the Dioxus installer and Rust backend.

## Next task

Implement `installer/protocol` as a Rust crate and add a dry-run backend. Then create an installation test on an empty disk using `bootc install to-disk --bootloader=systemd`.
