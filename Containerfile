# ShapeBit OS: console-only bootc image.
ARG FEDORA_VERSION=44
FROM quay.io/fedora/fedora-bootc:${FEDORA_VERSION}

LABEL org.opencontainers.image.title="ShapeBit OS" \
      org.opencontainers.image.url="https://shapebit.software" \
      org.opencontainers.image.source="https://github.com/shapebit-software/image"

# Files under rootfs/ are copied verbatim; their paths mirror the target system.
COPY rootfs/ /

RUN systemctl set-default multi-user.target

# Must stay last: validates the final image.
RUN bootc container lint
