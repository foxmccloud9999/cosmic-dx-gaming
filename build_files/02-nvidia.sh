#!/usr/bin/env bash
set -ouex pipefail

# 1. Read akmods-nvidia-open metadata and determine target kernel NVR
if [[ -f /tmp/akmods-nvidia/rpms/kmods/nvidia-vars ]]; then
    # shellcheck disable=SC1091
    source /tmp/akmods-nvidia/rpms/kmods/nvidia-vars
fi

mapfile -t KMOD_RPMS < <(find /tmp/akmods-nvidia/rpms/kmods -maxdepth 1 -name 'kmod-nvidia-*.rpm' | sort)
if [[ "${#KMOD_RPMS[@]}" -eq 0 ]]; then
    echo "ERROR: No kmod-nvidia-*.rpm found in /tmp/akmods-nvidia/rpms/kmods" >&2
    exit 1
fi

TARGET_KERNEL="${KERNEL_VERSION:-}"
if [[ -z "$TARGET_KERNEL" ]]; then
    TARGET_KERNEL="$(rpm -qp --requires "${KMOD_RPMS[0]}" | awk '/^kernel-uname-r/ {print $NF; exit}')"
fi

INSTALLED_KERNEL="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n1)"

# 2. Align Fedora COSMIC Atomic kernel to the exact kernel built against akmods-nvidia-open
if [[ -n "$TARGET_KERNEL" && "$INSTALLED_KERNEL" != "$TARGET_KERNEL" ]]; then
    KERNEL_RPMS_DIR="/tmp/akmods-nvidia/kernel-rpms"
    if [[ ! -d "$KERNEL_RPMS_DIR" ]]; then
        KERNEL_RPMS_DIR="/tmp/akmods/kernel-rpms"
    fi
    echo "Kernel mismatch detected (installed=${INSTALLED_KERNEL}, akmods=${TARGET_KERNEL}); aligning kernel from ${KERNEL_RPMS_DIR}"

    KERNEL_INSTALL_RPMS=()
    for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
        if rpm -q "$pkg" &>/dev/null; then
            match="$(find "$KERNEL_RPMS_DIR" -maxdepth 1 -name "${pkg}-${TARGET_KERNEL}.rpm" | head -n1)"
            if [[ -z "$match" ]]; then
                echo "ERROR: Missing ${pkg}-${TARGET_KERNEL}.rpm in ${KERNEL_RPMS_DIR}" >&2
                exit 1
            fi
            KERNEL_INSTALL_RPMS+=("$match")
        fi
    done

    if rpm -q kernel-uki-virt &>/dev/null; then
        uki_match="$(find "$KERNEL_RPMS_DIR" -maxdepth 1 -name "kernel-uki-virt-${TARGET_KERNEL}.rpm" | head -n1 || true)"
        if [[ -n "$uki_match" ]]; then
            KERNEL_INSTALL_RPMS+=("$uki_match")
        fi
    fi

    dnf5 install -y --allowerasing "${KERNEL_INSTALL_RPMS[@]}"

    # Remove old kernel RPMs so strictly one kernel exists in /lib/modules (required by bootc container lint)
    mapfile -t OLD_KERNEL_RPMS < <(
        rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
            'kernel' 'kernel-core' 'kernel-modules' 'kernel-modules-core' 'kernel-modules-extra' 'kernel-uki-virt' \
            | grep -vF "${TARGET_KERNEL}" || true
    )
    if [[ "${#OLD_KERNEL_RPMS[@]}" -gt 0 ]]; then
        rpm -e --nodeps "${OLD_KERNEL_RPMS[@]}"
    fi
    rm -rf "/lib/modules/${INSTALLED_KERNEL}"
fi

# 3. Install uBlue akmods addons (Secure Boot MOK certificate at /etc/pki/akmods/certs/akmods-ublue.der)
mapfile -t AKMODS_ADDONS < <(find /tmp/akmods/rpms/ublue-os -maxdepth 1 -name 'ublue-os-akmods-addons-*.rpm' 2>/dev/null || true)
if [[ "${#AKMODS_ADDONS[@]}" -gt 0 ]]; then
    dnf5 install -y "${AKMODS_ADDONS[@]}"
fi

# 4. Install uBlue NVIDIA addons (Negativo17 fedora-nvidia.repo, nvidia-container-toolkit.repo, SELinux policy)
mapfile -t NVIDIA_ADDONS < <(find /tmp/akmods-nvidia/rpms/ublue-os -maxdepth 1 -name 'ublue-os-nvidia-addons-*.rpm' 2>/dev/null || true)
if [[ "${#NVIDIA_ADDONS[@]}" -eq 0 ]]; then
    echo "ERROR: No ublue-os-nvidia-addons-*.rpm found in /tmp/akmods-nvidia/rpms/ublue-os" >&2
    exit 1
fi
dnf5 install -y "${NVIDIA_ADDONS[@]}"

# Temporarily disable RPM Fusion repos so RPM Fusion NVIDIA packages never conflict with Negativo17
if compgen -G "/etc/yum.repos.d/rpmfusion*.repo" >/dev/null; then
    dnf5 config-manager setopt "rpmfusion*".enabled=0
fi

# Temporarily enable Negativo17 & NVIDIA Container Toolkit repos installed by ublue-os-nvidia-addons
dnf5 config-manager setopt "fedora-nvidia*".enabled=1 nvidia-container-toolkit.enabled=1

# Install pre-bundled, version-matched NVIDIA userspace RPMs from akmods-nvidia-open alongside kmod-nvidia
ARCH="$(rpm -E '%{_arch}')"
shopt -s nullglob
NVIDIA_LOCAL_RPMS=(
    /tmp/akmods-nvidia/rpms/nvidia/*."${ARCH}".rpm
    /tmp/akmods-nvidia/rpms/nvidia/*.noarch.rpm
)
if [[ "$ARCH" == "x86_64" ]]; then
    NVIDIA_LOCAL_RPMS+=(/tmp/akmods-nvidia/rpms/nvidia/*.i686.rpm)
fi
shopt -u nullglob

if [[ "${#NVIDIA_LOCAL_RPMS[@]}" -eq 0 ]]; then
    echo "ERROR: No pre-bundled NVIDIA RPMs found in /tmp/akmods-nvidia/rpms/nvidia" >&2
    exit 1
fi

dnf5 install -y \
    "${KMOD_RPMS[@]}" \
    "${NVIDIA_LOCAL_RPMS[@]}" \
    egl-wayland \
    libva-nvidia-driver \
    nvidia-container-toolkit

# Verify kmod-nvidia and nvidia-driver ABI versions match exactly
KMOD_VERSION="$(rpm -q --qf '%{VERSION}' kmod-nvidia)"
DRIVER_VERSION="$(rpm -q --qf '%{VERSION}' nvidia-driver)"
if [[ "$KMOD_VERSION" != "$DRIVER_VERSION" ]]; then
    echo "ERROR: kmod-nvidia version (${KMOD_VERSION}) does not match nvidia-driver version (${DRIVER_VERSION})" >&2
    exit 1
fi

# Disable third-party NVIDIA repos again so runtime dnf state remains clean
dnf5 config-manager setopt "fedora-nvidia*".enabled=0 nvidia-container-toolkit.enabled=0

# Re-enable core RPM Fusion repos for 04-gaming.sh (keeping rpmfusion-nonfree-nvidia-driver disabled)
dnf5 config-manager setopt \
    rpmfusion-free.enabled=1 \
    rpmfusion-free-updates.enabled=1 \
    rpmfusion-nonfree.enabled=1 \
    rpmfusion-nonfree-updates.enabled=1

# 5. Load SELinux container policy for GPU passthrough if packaged
if [[ -f /usr/share/selinux/packages/nvidia-container.pp ]]; then
    semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp
fi

# 6. Configure kernel module options (DRM modeset + fbdev + VRAM preservation across suspend) & dracut preload
mkdir -p /etc/modprobe.d
cat <<'EOF' > /etc/modprobe.d/nvidia-modeset.conf
blacklist nouveau
options nouveau modeset=0
options nvidia-drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF

# Force-load NVIDIA and iGPU drivers in initramfs (prevents black screen on boot & preserves iGPU acceleration)
if [[ -f /usr/lib/dracut/dracut.conf.d/99-nvidia.conf ]]; then
    sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
    sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
fi

# 7. Enable NVIDIA persistence, container CDI, and optional power-management systemd units
systemctl enable nvidia-persistenced.service

for unit in \
    nvidia-cdi-refresh.service \
    nvidia-cdi-refresh.path \
    nvidia-powerd.service \
    nvidia-suspend.service \
    nvidia-hibernate.service \
    nvidia-resume.service \
    ublue-nvctk-cdi.service; do
    if systemctl list-unit-files "$unit" &>/dev/null; then
        systemctl enable "$unit"
    fi
done
