# Custom Fedora COSMIC Atomic spin with Universal Blue DX, Homebrew, ujust,
# NVIDIA open-kernel drivers, and Tier 1 desktop gaming stack.

ARG FEDORA_VERSION=45
ARG BASE_IMAGE=quay.io/fedora-ostree-desktops/cosmic-atomic
ARG AKMODS_FLAVOR=main
ARG IMAGE_NAME=cosmic-dx-gaming
ARG IMAGE_OWNER=foxmccloud9999

# Standalone OCI layers provided by Universal Blue
FROM ghcr.io/ublue-os/brew:latest AS brew
FROM ghcr.io/ublue-os/akmods:${AKMODS_FLAVOR}-${FEDORA_VERSION} AS akmods
FROM ghcr.io/ublue-os/akmods-nvidia-open:${AKMODS_FLAVOR}-${FEDORA_VERSION} AS akmods-nvidia

# Target bootable Fedora COSMIC Atomic base
FROM ${BASE_IMAGE}:${FEDORA_VERSION} AS base

ARG FEDORA_VERSION
ARG AKMODS_FLAVOR
ARG IMAGE_NAME
ARG IMAGE_OWNER

LABEL org.opencontainers.image.title="${IMAGE_NAME}" \
      org.opencontainers.image.description="Fedora COSMIC Atomic spin with Universal Blue DX tooling, Homebrew, ujust, NVIDIA open drivers, and Tier 1 gaming stack" \
      org.opencontainers.image.source="https://github.com/${IMAGE_OWNER}/${IMAGE_NAME}" \
      containers.bootc="1" \
      ostree.bootable="true"

# 1. Layer built-in Homebrew (unpacks tarball + systemd setup & update timers)
COPY --from=brew /system_files /

# 2. Layer declarative system files (kargs.d, sysusers, sysctl, polkit, ujust recipes, registries.d)
COPY system_files/ /

# 3. Execute modular build scripts with bind mounts (zero script/RPM residue in final image)
# Note: tmpfs is mounted at /tmp/build-work rather than /tmp so it does not mask /tmp/akmods*.
RUN --mount=type=bind,source=build_files,target=/ctx/build_files \
    --mount=type=bind,source=.,target=/ctx/repo \
    --mount=type=bind,from=akmods,source=/,target=/tmp/akmods \
    --mount=type=bind,from=akmods-nvidia,source=/,target=/tmp/akmods-nvidia \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=tmpfs,dst=/tmp/build-work \
    IMAGE_NAME="${IMAGE_NAME}" \
    IMAGE_OWNER="${IMAGE_OWNER}" \
    FEDORA_VERSION="${FEDORA_VERSION}" \
    bash -c 'set -ouex pipefail; \
      /ctx/build_files/01-ublue-base.sh && \
      /ctx/build_files/02-nvidia.sh && \
      /ctx/build_files/03-dx.sh && \
      /ctx/build_files/04-gaming.sh && \
      /ctx/build_files/05-finalize.sh'
