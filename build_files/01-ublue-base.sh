#!/usr/bin/env bash
set -ouex pipefail

RELEASE="$(rpm -E %fedora)"

# 1. Enable RPM Fusion Free & Nonfree for full multimedia & gaming codecs
dnf5 install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${RELEASE}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${RELEASE}.noarch.rpm"

# 2. Swap stub codecs for hardware-accelerated freeworld builds
if rpm -q ffmpeg-free &>/dev/null; then
    dnf5 swap -y ffmpeg-free ffmpeg --allowerasing
else
    dnf5 install -y --allowerasing ffmpeg
fi
dnf5 install -y --allowerasing \
    libavcodec-freeworld \
    mesa-va-drivers-freeworld \
    mesa-vdpau-drivers-freeworld \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly

# 3. Install Universal Blue core utilities (ujust, udev rules, LUKS TPM helpers) + QoL CLI
dnf5 install -y dnf5-plugins
dnf5 -y copr enable ublue-os/packages
dnf5 install -y \
    just \
    ublue-os-just \
    ublue-os-udev-rules \
    ublue-os-luks \
    gum \
    fastfetch \
    wl-clipboard \
    fzf \
    bat \
    eza \
    zoxide \
    btop \
    nvtop \
    lm_sensors \
    pciutils \
    usbutils \
    distrobox \
    jq

# Optional CLI extras that may vary by Fedora release
dnf5 install -y --skip-unavailable starship

dnf5 -y copr disable ublue-os/packages

# 4. Enable Homebrew systemd units (copied from ghcr.io/ublue-os/brew)
systemctl preset brew-setup.service brew-update.timer brew-upgrade.timer || true
systemctl enable brew-setup.service brew-update.timer brew-upgrade.timer

# 5. Enable automatic atomic OS background updates
if systemctl list-unit-files bootc-fetch-apply-updates.timer &>/dev/null; then
    systemctl enable bootc-fetch-apply-updates.timer
elif systemctl list-unit-files rpm-ostreed-automatic.timer &>/dev/null; then
    systemctl enable rpm-ostreed-automatic.timer
fi

# 6. Configure Cosign container image trust only when cosign.pub exists and IMAGE_OWNER is configured
IMAGE_NAME="${IMAGE_NAME:-cosmic-dx-gaming}"
IMAGE_OWNER="${IMAGE_OWNER:-YOUR_GITHUB_USERNAME}"
REGISTRIES_D_FILE="/etc/containers/registries.d/${IMAGE_NAME}.yaml"

if [[ -f /ctx/repo/cosign.pub && "${IMAGE_OWNER}" != "YOUR_GITHUB_USERNAME" ]]; then
    mkdir -p /etc/pki/containers
    cp /ctx/repo/cosign.pub "/etc/pki/containers/${IMAGE_NAME}.pub"

    OWNER_LOWER="${IMAGE_OWNER,,}"
    NAME_LOWER="${IMAGE_NAME,,}"
    IMAGE_REF="ghcr.io/${OWNER_LOWER}/${NAME_LOWER}"

    if [[ -f /etc/containers/policy.json ]]; then
        jq --arg ref "$IMAGE_REF" --arg key "/etc/pki/containers/${IMAGE_NAME}.pub" \
            '.transports.docker[$ref] = [{"type": "sigstoreSigned", "keyPath": $key, "signedIdentity": {"type": "matchRepository"}}]' \
            /etc/containers/policy.json > /tmp/build-work/policy.json
        mv /tmp/build-work/policy.json /etc/containers/policy.json
    fi

    if [[ -f "$REGISTRIES_D_FILE" ]]; then
        sed -i "s|ghcr.io/YOUR_GITHUB_USERNAME/cosmic-dx-gaming|${IMAGE_REF}|g" "$REGISTRIES_D_FILE"
    fi
else
    # Avoid leaving an unconfigured placeholder registries.d file in unsigned local builds
    rm -f "$REGISTRIES_D_FILE"
fi
