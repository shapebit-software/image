ARG FEDORA_VERSION=44
FROM quay.io/fedora/fedora-bootc:${FEDORA_VERSION}

# Minimal console-only ShapeBit OS host.
RUN dnf -y install \
      NetworkManager \
      openssh-server \
      systemd-boot-unsigned \
      util-linux \
      cryptsetup \
      btrfs-progs \
      jq \
      less \
      vim-minimal \
    && dnf -y clean all \
    && systemctl enable NetworkManager.service \
    && systemctl enable sshd.service \
    && systemctl set-default multi-user.target

COPY image/files/ /

RUN chmod 0755 /usr/lib/shapebit-os/shapebit-os-info \
    && systemctl enable shapebit-os-firstboot.service \
    && bootc container lint
