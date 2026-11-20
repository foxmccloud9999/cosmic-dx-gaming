# cosmic-dx-gaming

A custom **Fedora COSMIC Atomic** (`bootc`) desktop image combining **Universal Blue** ergonomics, **Aurora-DX / Bluefin-DX** developer tooling, **NVIDIA open-kernel drivers**, and a **Tier 1 desktop gaming stack**.

## What Is Included

- **Base OS**: Official Fedora COSMIC Atomic (`quay.io/fedora-ostree-desktops/cosmic-atomic:45`) with RPM Fusion Free & Nonfree hardware-accelerated codecs (`ffmpeg`, `mesa-va-drivers-freeworld`, GStreamer Freeworld/Ugly plugins).
- **Universal Blue Core**:
  - Built-in **Homebrew** (`ghcr.io/ublue-os/brew`) with first-boot user setup and background update/upgrade timers.
  - **`ujust`** (`ublue-os-just`) with curated, **COSMIC-safe** recipes (no GNOME/KDE-only commands).
  - Automatic background OS updates (`bootc-fetch-apply-updates.timer`).
- **NVIDIA Open Drivers**:
  - Pre-built `kmod-nvidia-open` from `ghcr.io/ublue-os/akmods-nvidia-open:main-45` (RTX 20-series / Turing and newer), automatic kernel NVR alignment, Negativo17 driver userspace + `.i686` 32-bit libs, `nvidia-container-toolkit`, SELinux container policy, declarative `kargs.d`, and suspend/resume services.
- **Developer Experience (DX)**:
  - `docker-ce` (+ Buildx & Compose), `podman`, `podman-compose`, `podman-tui`, `distrobox`, `skopeo`, `buildah`.
  - Virtualization: `qemu-kvm`, `libvirt`, `virt-manager`, `edk2-ovmf`, `swtpm`, `incus`.
  - Tools: VS Code (`code`), `git-lfs`, `gh`, `tmux`, `ripgrep`, `fd-find`, `bat`, `eza`, `zoxide`, `btop`, `nvtop`, `tailscale`, `cockpit`.
- **Gaming (Tier 1 Desktop Stack)**:
  - `gamescope`, `mangohud` (+ `.i686`), `gamemode` (+ `.i686`), `steam-devices` controller udev rules, `steam` (+ 32-bit Vulkan/Mesa/PipeWire libs), `vkBasalt`.
  - Bazzite-style `sysctl` tuning (`vm.max_map_count=2147483642`, `kernel.split_lock_mitigate=0`).
  - `ujust` helpers for Lutris, Heroic, ProtonPlus, Bottles, Prism Launcher, OBS VkCapture, and Sunshine.

---

## First-Time GitHub Setup

*(This repository is pre-configured for **`foxmccloud9999`**. If forking, run `just configure <your-github-username>` to update the owner/image references.)*

1. **Configure your GitHub username** (if forking, or changing the image name):
   ```bash
   just configure <your-github-username>
   ```
   *(Or replace the owner manually in `Containerfile`, `system_files/etc/containers/registries.d/cosmic-dx-gaming.yaml`, `Justfile`, and `README.md`.)*

2. **Generate Cosign signing keys** (uses local `cosign`, or automatically falls back to `podman` with `ghcr.io/sigstore/cosign/cosign:v2.4.1`):
   ```bash
   just generate-keys
   ```
   - Commit **`cosign.pub`** to your repository.
   - Copy the contents of **`cosign.key`** (already in `.gitignore`) into GitHub:
     **Repository Settings → Secrets and variables → Actions → New repository secret → `COSIGN_PRIVATE_KEY`**.

3. **Push to GitHub (`main`)**:
   - Ensure **Settings → Actions → General → Workflow permissions** allows **Read and write permissions**.
   - GitHub Actions (`.github/workflows/build.yml`) will build, lint, push to `ghcr.io/foxmccloud9999/cosmic-dx-gaming:latest`, and sign with Cosign.

4. **Make the GHCR package Public**:
   - After the first workflow run completes, go to your GitHub Profile → **Packages** → `cosmic-dx-gaming` → **Package settings** → **Change visibility → Public** so `bootc switch` can pull without authentication.

---

## Customization Tips

- **Bump Fedora 45 → 46**: Update `FEDORA_VERSION` in `Containerfile`, `.github/workflows/build.yml`, `Justfile`, and `system_files/usr/share/ublue-os/just/61-dx.just`.
- **Switch Steam to Flatpak instead of native RPM**: Edit `build_files/04-gaming.sh` (remove `steam` and the `.i686` packages; keep `gamescope`, `mangohud`, `gamemode`, `steam-devices`, `vulkan-tools`, `vulkan-loader` on the host) and `02-nvidia.sh` if you also want to drop `nvidia-driver-libs.i686`.

---

## Local Build & VM Verification

```bash
# Build OCI image locally
just build foxmccloud9999

# Run bootc container lint + ujust syntax validation
just lint

# Optional: generate a QEMU/KVM QCOW2 disk image in ./output/qcow2/disk.qcow2
# (Pulls ghcr.io/foxmccloud9999/cosmic-dx-gaming:latest into root Podman storage if not already built/present as root)
just build-qcow2
```

---

## Safe Bare-Metal Deployment

On an existing Fedora Atomic / Fedora COSMIC Atomic machine:

1. **Pin your working deployment** so GRUB always keeps a guaranteed rollback:
   ```bash
   sudo ostree admin pin 0
   ```
2. **Rebase to the unverified registry first** (only needed on the initial switch so your host pulls `/etc/pki/containers/cosmic-dx-gaming.pub` and `/etc/containers/policy.json` trust configuration):
   ```bash
   sudo bootc switch --transport registry ghcr.io/foxmccloud9999/cosmic-dx-gaming:latest
   # Or if using rpm-ostree:
   # sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/foxmccloud9999/cosmic-dx-gaming:latest
   systemctl reboot
   ```
3. **Switch to signed verification enforcement**:
   ```bash
   sudo bootc switch --enforce-container-sigpolicy ghcr.io/foxmccloud9999/cosmic-dx-gaming:latest
   # Or via rpm-ostree:
   # sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/foxmccloud9999/cosmic-dx-gaming:latest
   systemctl reboot
   ```

---

## Post-Install Setup (`ujust`)

```bash
# 1. If Secure Boot is enabled, enroll the Universal Blue akmods MOK key (password: universalblue)
ujust enroll-secure-boot-key

# 2. Add your user to docker, libvirt, incus-admin, and gamemode groups (then log out / reboot)
ujust dx-group

# 3. Install Lutris, Heroic, ProtonPlus, Bottles, OBS VkCapture, and Prism Launcher
ujust install-gaming-flatpaks

# 4. Optional: install curated developer CLI tools via Homebrew & enable Docker NVIDIA GPU support
ujust install-dx-brew
ujust configure-docker-nvidia

# 5. Verify NVIDIA driver, Vulkan, VA-API, sysctl, Gamescope, and Gamemode
ujust gaming-check
```

---

## Troubleshooting COSMIC + NVIDIA

- **Secure Boot blocks `nvidia` kernel module**: Run `ujust enroll-secure-boot-key`, reboot, and enroll the MOK in the blue UEFI screen using password `universalblue`.
- **XWayland game scaling / VRR quirks under `cosmic-comp`**: Launch the game wrapped in Gamescope (for example in Steam launch options: `gamescope -W 2560 -H 1440 -f -r 144 -- %command%`).
- **Missing kernel arguments after an `rpm-ostree` rebase**: Run `ujust configure-nvidia-kargs` and reboot.
