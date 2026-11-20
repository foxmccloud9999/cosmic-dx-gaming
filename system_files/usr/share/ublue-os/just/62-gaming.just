# Gaming & NVIDIA recipes

# Install curated gaming Flatpaks (Lutris, Heroic, ProtonPlus, Bottles, OBS, Prism)
install-gaming-flatpaks:
    #!/usr/bin/env bash
    set -euo pipefail
    flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install --system -y flathub \
        net.lutris.Lutris \
        com.heroicgameslauncher.hgl \
        com.vysp3r.ProtonPlus \
        com.github.tchx84.Flatseal \
        com.usebottles.bottles \
        com.github.Matoking.protontricks \
        com.obsproject.Studio \
        com.obsproject.Studio.Plugin.OBSVkCapture \
        org.prismlauncher.PrismLauncher
    echo "Gaming Flatpaks installed."

# Enroll Universal Blue akmods Secure Boot MOK key (password: universalblue)
enroll-secure-boot-key:
    #!/usr/bin/env bash
    set -euo pipefail
    KEY_PATH="/etc/pki/akmods/certs/akmods-ublue.der"
    if [[ ! -f "$KEY_PATH" ]]; then
        echo "ERROR: Secure Boot MOK certificate not found at $KEY_PATH" >&2
        exit 1
    fi
    echo "Importing $KEY_PATH into MOK..."
    echo "When prompted, enter password: universalblue"
    echo "Reboot afterward and choose 'Enroll MOK' -> 'Continue' -> 'Yes' -> 'universalblue'."
    sudo mokutil --import "$KEY_PATH"

# Apply NVIDIA kernel arguments via rpm-ostree (fallback if not already applied by bootc kargs.d)
configure-nvidia-kargs:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo rpm-ostree kargs \
        --append-if-missing=rd.driver.blacklist=nouveau \
        --append-if-missing=modprobe.blacklist=nouveau \
        --append-if-missing=nvidia-drm.modeset=1 \
        --append-if-missing=nvidia-drm.fbdev=1 \
        --delete-if-present=nomodeset
    echo "NVIDIA kernel arguments updated. Reboot to apply."

# Install LizardByte Sunshine game-streaming Flatpak and print uinput guidance
setup-sunshine:
    #!/usr/bin/env bash
    set -euo pipefail
    flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install --system -y flathub dev.lizardbyte.app.Sunshine
    echo "Sunshine Flatpak installed."
    echo "For virtual controller input (uinput), follow Sunshine's Flatpak post-install udev prompt:"
    echo "  flatpak run --command=additional-install.sh dev.lizardbyte.app.Sunshine"

# Run diagnostics for GPU, Vulkan, VA-API, sysctl gaming tuning, Gamemode, and Gamescope
gaming-check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== NVIDIA Driver ==="
    nvidia-smi --query-gpu=name,driver_version,vbios_version --format=csv,noheader || echo "nvidia-smi unavailable"
    echo ""
    echo "=== Kernel Args ==="
    cat /proc/cmdline
    echo ""
    echo "=== Gaming Sysctl ==="
    sysctl vm.max_map_count kernel.split_lock_mitigate net.core.netdev_max_backlog fs.file-max
    echo ""
    echo "=== Vulkan Summary ==="
    vulkaninfo --summary 2>/dev/null | head -n 30 || echo "vulkaninfo unavailable"
    echo ""
    echo "=== VA-API ==="
    vainfo 2>/dev/null | head -n 15 || echo "vainfo unavailable"
    echo ""
    echo "=== Gamescope & Gamemode ==="
    gamescope --version || true
    gamemoded -t || true
