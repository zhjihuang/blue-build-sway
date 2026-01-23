#!/usr/bin/bash

set -ouex pipefail

KERNEL_LOCK="kernel{,-core,-modules,-modules-core,-modules-extra,-tools,-tools-lib,-headers,-devel,-devel-matched}"
KERNEL_SUFFIX="surface"
REPOSITORY_SURFACE="https://pkg.surfacelinux.com/fedora/linux-surface.repo"
PACKAGES_KERNEL_DEFAULT=(
  kernel
  kernel-core
  kernel-modules
  kernel-modules-core
  kernel-modules-extra
)
PACKAGES_KERNEL_SURFACE=(
  kernel-surface
  iptsd
  libwacom-surface
  surface-secureboot
  surface-control
)

# remove kernel locks
dnf5 versionlock delete ${KERNEL_LOCK} 

# Add the Surface Linux repo
dnf5 config-manager addrepo --from-repofile=${REPOSITORY_SURFACE}

# Install the Surface Linux kernel and related packages
dnf5 -y install --allowerasing "${PACKAGES_KERNEL_SURFACE[@]}"

# Remove the default Fedora kernel and related packages
dnf5 -y remove "${PACKAGES_KERNEL_DEFAULT[@]}"

# Rebuild initramfs
KERNEL_QUALIFIED="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
/usr/bin/dracut --no-hostonly --kver "${KERNEL_QUALIFIED}" --reproducible -v --add ostree -f "/lib/modules/${KERNEL_QUALIFIED}/initramfs.img"
chmod 0600 "/lib/modules/${KERNEL_QUALIFIED}/initramfs.img"

# Prevent kernel from upgrading again
dnf5 versionlock add ${KERNEL_LOCK}

dnf5 clean all
