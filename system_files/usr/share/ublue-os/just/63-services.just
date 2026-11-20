# System maintenance and optional service recipes

# Update OS image, Flatpaks, Homebrew packages, and Distrobox containers
update:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Updating Atomic OS ==="
    if command -v bootc >/dev/null 2>&1 && bootc status >/dev/null 2>&1; then
        sudo bootc upgrade
    else
        rpm-ostree upgrade
    fi
    echo "=== Updating Flatpaks ==="
    if command -v flatpak >/dev/null 2>&1; then
        flatpak update -y
    fi
    echo "=== Updating Homebrew ==="
    if command -v brew >/dev/null 2>&1; then
        brew update && brew upgrade
    fi
    echo "=== Updating Distrobox Containers ==="
    if command -v distrobox >/dev/null 2>&1; then
        distrobox upgrade --all
    fi

# Toggle automatic background OS update timer
toggle-updates:
    #!/usr/bin/env bash
    set -euo pipefail
    TIMER="bootc-fetch-apply-updates.timer"
    if ! systemctl list-unit-files "$TIMER" >/dev/null 2>&1; then
        TIMER="rpm-ostreed-automatic.timer"
    fi
    if systemctl is-enabled "$TIMER" >/dev/null 2>&1; then
        sudo systemctl disable --now "$TIMER"
        echo "Disabled $TIMER."
    else
        sudo systemctl enable --now "$TIMER"
        echo "Enabled $TIMER."
    fi

# Toggle Tailscale daemon
toggle-tailscale:
    #!/usr/bin/env bash
    set -euo pipefail
    if systemctl is-enabled tailscaled.service >/dev/null 2>&1; then
        sudo systemctl disable --now tailscaled.service
        echo "Tailscale disabled."
    else
        sudo systemctl enable --now tailscaled.service
        echo "Tailscale enabled. Connect with: sudo tailscale up"
    fi

# Toggle Cockpit web management console (https://localhost:9090)
toggle-cockpit:
    #!/usr/bin/env bash
    set -euo pipefail
    if systemctl is-enabled cockpit.socket >/dev/null 2>&1; then
        sudo systemctl disable --now cockpit.socket
        echo "Cockpit disabled."
    else
        sudo systemctl enable --now cockpit.socket
        echo "Cockpit enabled at https://localhost:9090"
    fi

# Enroll TPM2 automatic unlock for LUKS encrypted root volume
setup-luks-tpm-unlock:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v ublue-setup-luks-tpm-unlock >/dev/null 2>&1; then
        sudo ublue-setup-luks-tpm-unlock
        exit 0
    fi
    if ! command -v systemd-cryptenroll >/dev/null 2>&1; then
        echo "ERROR: systemd-cryptenroll not found." >&2
        exit 1
    fi
    echo "Detected LUKS block devices:"
    lsblk -fp | grep -E 'crypto_LUKS|NAME' || true
    read -r -p "Enter LUKS partition path (e.g. /dev/nvme0n1p3): " LUKS_DEV
    if [[ -z "$LUKS_DEV" || ! -b "$LUKS_DEV" ]]; then
        echo "ERROR: Invalid block device '$LUKS_DEV'" >&2
        exit 1
    fi
    if command -v gum >/dev/null 2>&1; then
        gum confirm "Enroll TPM2 unlock (PCR 7) on ${LUKS_DEV}?"
    else
        read -r -p "Enroll TPM2 unlock (PCR 7) on ${LUKS_DEV}? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]]
    fi
    sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 "$LUKS_DEV"
    echo "TPM2 enrollment complete. Verify on next reboot."

# Pin the currently booted OSTree deployment so it is never pruned during upgrades
pin-current-deployment:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo ostree admin pin 0
    rpm-ostree status

# Clean unused Podman/Docker images, unused Flatpak runtimes, and Homebrew cache
clean-system:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v podman >/dev/null 2>&1; then
        podman system prune -af
    fi
    if command -v docker >/dev/null 2>&1 && systemctl is-active docker.service >/dev/null 2>&1; then
        docker system prune -af
    fi
    if command -v flatpak >/dev/null 2>&1; then
        flatpak uninstall --unused -y
    fi
    if command -v brew >/dev/null 2>&1; then
        brew cleanup --prune=all
    fi
    echo "Cleanup complete."
