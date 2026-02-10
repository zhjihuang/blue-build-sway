#!/usr/bin/bash

set -ouex pipefail

REPOSITORY_SURFACE="https://pkg.surfacelinux.com/fedora/linux-surface.repo"
KERNEL_LOCK=(
  'kernel'
  'kernel-core'
  'kernel-modules'
  'kernel-modules-core'
  'kernel-modules-extra'
  'kernel-tools'
  'kernel-tools-lib'
  'kernel-headers'
  'kernel-devel'
  'kernel-devel-matched'
)
PACKAGES_KERNEL_DEFAULT=(
  'kernel'
  'kernel-core'
  'kernel-modules'
  'kernel-modules-core'
  'kernel-modules-extra'
)
PACKAGES_KERNEL_SURFACE=(
  'kernel-surface'
  'iptsd'
  'libwacom-surface'
  'surface-secureboot'
  'surface-control'
)

# remove kernel locks
dnf5 versionlock \
     delete \
     ${KERNEL_LOCK[@]}

# Add the Surface Linux repo
dnf5 config-manager \
     addrepo \
     --from-repofile=${REPOSITORY_SURFACE}

# Install the Surface Linux kernel and related packages
dnf5 install \
     --assumeyes \
     --allowerasing \
     ${PACKAGES_KERNEL_SURFACE[@]}

# Remove the default Fedora kernel and related packages
dnf5 remove \
     --assumeyes \
     ${PACKAGES_KERNEL_DEFAULT[@]}

# Prevent kernel from upgrading again
dnf5 versionlock add ${KERNEL_LOCK[@]}

dnf5 clean all
