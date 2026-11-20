#!/usr/bin/env bash
set -ouex pipefail

# 1. Configure external developer repositories (Docker CE, VS Code, Tailscale)
curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
curl -fsSL https://pkgs.tailscale.com/stable/fedora/tailscale.repo -o /etc/yum.repos.d/tailscale.repo

rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat <<'EOF' > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 2. Install DevMode (DX) containers, virtualization, and core tooling
# Note: VS Code installs into /usr/share/code (bootc/OSTree-safe; avoids /opt trap)
dnf5 install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    podman-compose \
    podman-tui \
    skopeo \
    buildah \
    qemu-kvm \
    libvirt \
    libvirt-nss \
    virt-manager \
    virt-viewer \
    edk2-ovmf \
    swtpm \
    swtpm-tools \
    incus \
    incus-tools \
    code \
    git-lfs \
    gh \
    tmux \
    ripgrep \
    fd-find \
    make \
    gcc \
    gcc-c++ \
    cmake \
    tailscale \
    cockpit-system \
    cockpit-podman \
    cockpit-machines

# 3. Disable third-party DX repos after install to keep runtime system clean
for repo_file in /etc/yum.repos.d/docker-ce.repo /etc/yum.repos.d/vscode.repo /etc/yum.repos.d/tailscale.repo; do
    if [[ -f "$repo_file" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$repo_file"
    fi
done

# 4. Enable container and virtualization sockets/services (Tailscale & Cockpit stay off until toggled via ujust)
systemctl enable \
    docker.socket \
    podman.socket \
    libvirtd.service \
    incus.socket
