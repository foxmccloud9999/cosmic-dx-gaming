#!/usr/bin/env bash
set -ouex pipefail

# 1. Ensure ujust discovers our custom recipe entrypoint and validate syntax
if [[ -f /usr/share/ublue-os/justfile ]]; then
    if ! grep -q '60-custom.just' /usr/share/ublue-os/justfile && \
       ! grep -q '60-custom.just' /usr/share/ublue-os/just/*.just 2>/dev/null; then
        echo 'import "/usr/share/ublue-os/just/60-custom.just"' >> /usr/share/ublue-os/justfile
    fi
fi

just --justfile /usr/share/ublue-os/just/60-custom.just --list

# 2. Verify kernel module linkage and regenerate OSTree-aware initramfs for the single installed kernel
QUALIFIED_KERNEL="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n1)"
depmod -a "$QUALIFIED_KERNEL"
modinfo -k "$QUALIFIED_KERNEL" nvidia >/dev/null

export DRACUT_NO_XATTR=1
/usr/bin/dracut \
    --no-hostonly \
    --kver "$QUALIFIED_KERNEL" \
    --reproducible \
    --zstd \
    -v \
    --add ostree \
    -f "/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"
chmod 0600 "/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"

# 3. Clean package caches and transient logs while preserving /var/cache/libdnf5 mount and RPM DB
dnf5 clean all
find /var/cache -mindepth 1 -maxdepth 1 ! -name libdnf5 -exec rm -rf {} +
rm -rf /var/log/dnf* /tmp/build-work/*

# 4. Run bootc container structural lint so image defects fail in CI before pushing
bootc container lint
