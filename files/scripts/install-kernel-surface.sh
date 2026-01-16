#!/bin/bash

set -ouex pipefail

# remove kernel locks
dnf5 versionlock delete kernel{,-core,-modules,-modules-core,-modules-extra,-tools,-tools-lib,-headers,-devel,-devel-matched}

# Add the Surface Linux repo
dnf5 config-manager \
    addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo

# Install the Surface Linux kernel and related packages
dnf5 -y install --allowerasing kernel-surface iptsd libwacom-surface surface-secureboot surface-control

# Remove the default Fedora kernel and related packages
dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

tee /usr/lib/modules-load.d/surface.conf << EOF
# Only on AMD models
pinctrl_amd

# Surface Book 2
pinctrl_sunrisepoint

# For Surface Laptop 3/Surface Book 3
pinctrl_icelake

# For Surface Laptop 4/Surface Laptop Studio
pinctrl_tigerlake

# For Surface Pro 9/Surface Laptop 5
pinctrl_alderlake

# For Surface Pro 10/Surface Laptop 6
pinctrl_meteorlake

# Only on Intel models
intel_lpss
intel_lpss_pci

# Add modules necessary for Disk Encryption via keyboard
surface_aggregator
surface_aggregator_registry
surface_aggregator_hub
surface_hid_core
8250_dw

# Surface Laptop 3/Surface Book 3 and later
surface_hid
surface_kbd
EOF

KERNEL_SUFFIX="surface"
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

# Prevent kernel stuff from upgrading again
dnf5 versionlock add kernel{,-core,-modules,-modules-core,-modules-extra,-tools,-tools-lib,-headers,-devel,-devel-matched}

SURFACE_PACKAGES=(
    iptsd
    libcamera
    libcamera-tools
    libcamera-gstreamer
    libcamera-ipa
    pipewire-plugin-libcamera
)

dnf5 install --assumeyes --skip-unavailable "${SURFACE_PACKAGES[@]}"

dnf5 clean all
