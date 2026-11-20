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
    echo "Kernel mismatch detected (installed=${INSTALLED_KERNEL}, akmods=${TARGET_KERNEL}); aligning kernel from /tmp/akmods/kernel-rpms"

    KERNEL_INSTALL_RPMS=()
    for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
        if rpm -q "$pkg" &>/dev/null; then
            match="$(find /tmp/akmods/kernel-rpms -maxdepth 1 -name "${pkg}-${TARGET_KERNEL}.rpm" | head -n1)"
            if [[ -z "$match" ]]; then
                echo "ERROR: Missing ${pkg}-${TARGET_KERNEL}.rpm in /tmp/akmods/kernel-rpms" >&2
                exit 1
            fi
            KERNEL_INSTALL_RPMS+=("$match")
        fi
    done

    if rpm -q kernel-uki-virt &>/dev/null; then
        uki_match="$(find /tmp/akmods/kernel-rpms -maxdepth 1 -name "kernel-uki-virt-${TARGET_KERNEL}.rpm" | head -n1 || true)"
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

# Prevent RPM Fusion NVIDIA repo from conflicting with Negativo17 driver packaging
if [[ -f /etc/yum.repos.d/rpmfusion-nonfree-nvidia-driver.repo ]]; then
    sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/rpmfusion-nonfree-nvidia-driver.repo
fi

# Temporarily enable Negativo17 & NVIDIA Container Toolkit repos installed by ublue-os-nvidia-addons
for repo_file in /etc/yum.repos.d/negativo17-fedora-nvidia.repo /etc/yum.repos.d/nvidia-container-toolkit.repo; do
    if [[ -f "$repo_file" ]]; then
        sed -i 's@enabled=0@enabled=1@g' "$repo_file"
    fi
done

# Pin userspace driver packages to the exact ABI version of kmod-nvidia-open.
# Strip any leading RPM epoch (e.g. "3:") so dnf glob matching works cleanly across Negativo17 packaging.
NV_VER="${NVIDIA_AKMOD_VERSION:-}"
if [[ -n "$NV_VER" ]]; then
    NV_VER_CLEAN="${NV_VER#*:}"
    NV_SUFFIX="-${NV_VER_CLEAN}*"
else
    NV_SUFFIX=""
fi

dnf5 install -y --setopt=install_weak_deps=False \
    "${KMOD_RPMS[@]}" \
    "nvidia-driver${NV_SUFFIX}" \
    "nvidia-driver-cuda${NV_SUFFIX}" \
    "nvidia-driver-cuda-libs${NV_SUFFIX}" \
    "nvidia-driver-libs${NV_SUFFIX}" \
    "nvidia-driver-libs${NV_SUFFIX}.i686" \
    "nvidia-settings${NV_SUFFIX}" \
    "nvidia-persistenced${NV_SUFFIX}" \
    "libnvidia-fbc${NV_SUFFIX}" \
    libva-nvidia-driver \
    nvidia-container-toolkit

# Disable third-party NVIDIA repos again so runtime dnf state remains clean
for repo_file in /etc/yum.repos.d/negativo17-fedora-nvidia.repo /etc/yum.repos.d/nvidia-container-toolkit.repo; do
    if [[ -f "$repo_file" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$repo_file"
    fi
done

# 5. Load SELinux container policy for GPU passthrough if packaged
if [[ -f /usr/share/selinux/packages/nvidia-container.pp ]]; then
    semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp
fi

# 6. Configure kernel module options (DRM modeset + fbdev + VRAM preservation across suspend)
mkdir -p /etc/modprobe.d
cat <<'EOF' > /etc/modprobe.d/nvidia-modeset.conf
blacklist nouveau
options nouveau modeset=0
options nvidia-drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF

# 7. Enable NVIDIA power management, persistence, and container CDI systemd units
systemctl enable \
    nvidia-suspend.service \
    nvidia-hibernate.service \
    nvidia-resume.service \
    nvidia-persistenced.service

if systemctl list-unit-files ublue-nvctk-cdi.service &>/dev/null; then
    systemctl enable ublue-nvctk-cdi.service
fi
