# Developer Experience (DX) recipes

# Add current user to docker, libvirt, incus-admin, and gamemode groups
dx-group:
    #!/usr/bin/env bash
    set -euo pipefail
    GROUPS_NEEDED=(docker libvirt incus-admin gamemode)
    echo "Ensuring system groups exist in /etc/group (OSTree nss-altfiles compatibility)..."
    for grp in "${GROUPS_NEEDED[@]}"; do
        if ! grep -q "^${grp}:" /etc/group; then
            if grep -q "^${grp}:" /usr/lib/group; then
                grep "^${grp}:" /usr/lib/group | sudo tee -a /etc/group >/dev/null
            else
                sudo groupadd -f "$grp"
            fi
        fi
        sudo usermod -aG "$grp" "$USER"
        echo "  -> Added $USER to $grp"
    done
    echo "Done! Log out or reboot for group memberships to take effect."

# Configure NVIDIA Container Toolkit CDI runtime for Docker
configure-docker-nvidia:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl enable --now docker.socket docker.service
    sudo systemctl restart docker
    echo "Docker NVIDIA runtime configured. Test with: docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi"

# Create a GPU-enabled Distrobox development container (default: fedora-toolbox:45)
setup-distrobox-dev name="dev" image="quay.io/fedora/fedora-toolbox:45":
    #!/usr/bin/env bash
    set -euo pipefail
    if distrobox list --no-color | awk -F'|' 'NR>1 {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | grep -qx "{{name}}"; then
        echo "Distrobox '{{name}}' already exists. Enter it with: distrobox enter {{name}}"
        exit 0
    fi
    distrobox create --name "{{name}}" --image "{{image}}" --nvidia --yes
    echo "Created '{{name}}' with NVIDIA passthrough. Enter with: distrobox enter {{name}}"

# Install curated cloud-native developer CLI tools via Homebrew
install-dx-brew:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is not yet in PATH. Checking brew-setup.service..."
        sudo systemctl start brew-setup.service
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
    brew install \
        neovim \
        lazygit \
        lazydocker \
        mise \
        direnv \
        atuin \
        kubectl \
        helm \
        k9s \
        terraform \
        yq
    echo "DX Homebrew tools installed."
