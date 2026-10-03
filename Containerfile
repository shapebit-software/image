# ShapeBit OS: console-only bootc image, booted by systemd-boot from a signed UKI.
# This is the unsealed system; Containerfile.seal adds the UKI (see
# scripts/image.sh). Signing needs the Secure Boot keys as build secrets PK,
# KEK, and db (.key and .crt each), and KEYS_ID, which changes with them.
# Only signed binaries and public keys reach the image.
ARG FEDORA_VERSION=44
FROM quay.io/fedora/fedora-bootc:${FEDORA_VERSION} AS system

LABEL org.opencontainers.image.title="ShapeBit OS" \
      org.opencontainers.image.url="https://shapebit.software" \
      org.opencontainers.image.source="https://github.com/shapebit-software/image"

# Files under rootfs/ are copied verbatim; their paths mirror the target system.
COPY rootfs/ /

# The base image ships only GRUB; bootc installs systemd-boot from this package.
# dnf state in /var and /run is removed, since bootc ignores it on install.
RUN dnf -y install systemd-boot-unsigned && dnf clean all && \
    rm -rf /var/log/dnf5.log /var/lib/dnf /var/cache/libdnf5 /var/cache/ldconfig /run/dnf

RUN systemctl set-default multi-user.target && \
    systemctl preset tpm2-firstboot.service systemd-homed-firstboot.service

# Logins for systemd-homed users need pam_systemd_home. authselect's checksum
# in /var is dropped, as in the base image; the configuration lives in /etc.
RUN authselect enable-feature with-systemd-homed && rm -r /var/lib/authselect

# The initramfs must carry /usr/lib/composefs/setup-root-conf.toml, so it is
# rebuilt after rootfs/ is in place.
RUN kernel=$(basename /usr/lib/modules/*) && \
    dracut --force "/usr/lib/modules/$kernel/initramfs.img" "$kernel"

# Signing tools, used by the stages below and never part of the final image.
FROM system AS tools
RUN dnf -y install sbsigntools efitools && mkdir /out

# systemd-boot signed with db; bootctl installs the *.signed copy when present.
FROM tools AS bootloader
ARG KEYS_ID
RUN --mount=type=secret,id=db.key --mount=type=secret,id=db.crt \
    sbsign --key /run/secrets/db.key --cert /run/secrets/db.crt \
      --output /out/systemd-bootx64.efi.signed \
      /usr/lib/systemd/boot/efi/systemd-bootx64.efi

# Keys that systemd-boot enrolls when the firmware is in setup mode; bootc
# copies them to the ESP. Each list is signed by the key above it.
FROM tools AS keys
ARG OWNER_GUID=6e2b6a3c-7a1e-4d0e-9d38-5f0c2b9a4e11
ARG KEYS_ID
RUN --mount=type=secret,id=PK.key --mount=type=secret,id=PK.crt \
    --mount=type=secret,id=KEK.key --mount=type=secret,id=KEK.crt \
    --mount=type=secret,id=db.crt <<'EOF'
set -euo pipefail
cd /out
for name in PK KEK db; do
  cert-to-efi-sig-list -g "$OWNER_GUID" "/run/secrets/$name.crt" "$name.esl"
done
sign-efi-sig-list -g "$OWNER_GUID" -k /run/secrets/PK.key -c /run/secrets/PK.crt PK PK.esl PK.auth
sign-efi-sig-list -g "$OWNER_GUID" -k /run/secrets/PK.key -c /run/secrets/PK.crt KEK KEK.esl KEK.auth
sign-efi-sig-list -g "$OWNER_GUID" -k /run/secrets/KEK.key -c /run/secrets/KEK.crt db db.esl db.auth
rm ./*.esl
EOF

FROM system
COPY --from=bootloader /out/ /usr/lib/systemd/boot/efi/
COPY --from=keys /out/ /usr/lib/bootc/install/secureboot-keys/auto/
# Identifies this build; last, so a new version rebuilds only this layer.
ARG IMAGE_VERSION
RUN test -n "$IMAGE_VERSION" && echo "IMAGE_VERSION=$IMAGE_VERSION" >>/usr/lib/os-release
RUN bootc container lint
