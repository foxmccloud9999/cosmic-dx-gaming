#!/usr/bin/env bash
set -ouex pipefail

# Tier 1 Desktop Gaming Stack (stock mainline kernel + hardware codecs + Steam + wrappers)
#
# Prefer Flatpak Steam over native RPM Steam?
# Remove `steam` and the `.i686` multilib packages below, keeping `gamescope`,
# `mangohud`, `gamemode`, `steam-devices`, `vulkan-tools`, and `vulkan-loader`
# on the host image, then install `com.valvesoftware.Steam` via Flathub.
dnf5 install -y \
    gamescope \
    mangohud \
    mangohud.i686 \
    gamemode \
    gamemode.i686 \
    steam-devices \
    vulkan-tools \
    vulkan-loader \
    vulkan-loader.i686 \
    pipewire-alsa.i686 \
    steam

# Optional post-processing layer (skipped cleanly if unavailable in current Fedora repos)
dnf5 install -y --skip-unavailable vkBasalt
