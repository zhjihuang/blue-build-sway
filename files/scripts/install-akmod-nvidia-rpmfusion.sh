#!/usr/bin/env bash

# Copyright 2025 Universal Blue
# Copyright 2025 The Secureblue Authors
# Copyright 2025 The BlueBuild Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://apache.org
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

set -oue pipefail

mkdir -p "/var/tmp"
chmod 1777 "/var/tmp"

initial-setup() {
  RELEASE="$(rpm -E '%fedora')"
  if [[ "$IMAGE_NAME" == *'surface'* ]]; then
    KERNEL_NAME='kernel-surface'
    KERNEL_DEVEL_NAME='kernel-surface-devel'
  else
    KERNEL_NAME='kernel'
    KERNEL_DEVEL_NAME='kernel-devel-matched'
  fi
  KERNEL_VERSION="$(rpm -q ${KERNEL_NAME} --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
  DRIVER_VERSION="${DRIVER_VERSION}:580"
  if [[ "${DRIVER_VERSION}" =~ ^[0-9]+$ ]]; then
    # If we are on Fedora 44 or newer, version 580 requires the legacy suffix
    if [[ "${RELEASE}" -ge 44 ]]; then
      DRIVER_SUFFIX="-${DRIVER_VERSION}xx"
    else
      # On Fedora 43 or older, version 580 is mainstream (no suffix)
      DRIVER_SUFFIX=""
    fi
  else
    DRIVER_SUFFIX=""
  fi
  # -------------------------------- 
  # Kernel module
  # ================================
  KERNEL_DEVEL_VERSION="${KERNEL_DEVEL_NAME}-$(rpm -q ${KERNEL_NAME} --queryformat '%{VERSION}')"
  # TODO: KERNEL_DEVEL_VERSION="${KERNEL_DEVEL_NAME}-$(rpm -q ${KERNEL_NAME} --queryformat '%{VERSION}-%{RELEASE}')"
  AKMOD_PACKAGES_EXCLUDE='kernel-core,kernel-devel,kernel-devel-matched,kernel-modules-core'
  AKMOD_PACKAGES=(
    'akmods'
    'gcc-c++'
  )
  # -------------------------------- 
  # Packages
  # ================================
  NVIDIA_FREE_PACKAGES_LIST=(
    'libva-nvidia-driver'
  )
  NVIDIA_NONFREE_PACKAGES_LIST=(
    # -------------------------------- 
    # Already pulled by akmod-nvidia
    # --------------------------------
    # 'nvidia-settings'
    # 'xorg-x11-drv-nvidia${DRIVER_SUFFIX}'
    # 'xorg-x11-drv-nvidia${DRIVER_SUFFIX}-cuda-libs'
    # ================================
    "xorg-x11-drv-nvidia${DRIVER_SUFFIX}-power"
    "xorg-x11-drv-nvidia${DRIVER_SUFFIX}-cuda"
  )
  NVIDIA_PACKAGES_LIST=(
    ${NVIDIA_FREE_PACKAGES_LIST[@]}
    ${NVIDIA_NONFREE_PACKAGES_LIST[@]}
  )
  PACKAGES_CLEANUP_KERNEL=(
    'kernel-devel'
    'kernel-headers'
  )
  if [[ "$IMAGE_NAME" == *'surface'* ]]; then
    PACKAGES_INSTALL_KERNEL+=(${KERNEL_DEVEL_VERSION})
    PACKAGES_CLEANUP_KERNEL+=('surface-kernel-devel')
  fi
  PACKAGES_CLEANUP=(
    'akmods'
    ${PACKAGES_CLEANUP_KERNEL[@]}
  )
  FILES_CLEANUP=(
    'nvidia-container.pp'
    '/etc/yum.repos.d/nvidia-container-toolkit.repo'
    "/etc/yum.repos.d/rpmfusion-free-release-${RELEASE}.noarch.rpm"
    "/etc/yum.repos.d/rpmfusion-nonfree-release-${RELEASE}.noarch.rpm"
  )
}

install-rpmfusion() {
  local REPOSITORIES=(
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${RELEASE}.noarch.rpm"
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${RELEASE}.noarch.rpm"
  )
  dnf install \
      --assumeyes \
      ${REPOSITORIES[@]}
}

install-kernel-modules-43() {
  local NVIDIA_KERNEL_PACKAGES=()
  local DNF_DEFINE_ARGS=()

  if [[ "$IMAGE_NAME" == *'nvidia-open'* ]]; then
    NVIDIA_KERNEL_PACKAGES=(
      "akmod-nvidia-open${DRIVER_SUFFIX}"
      'nvidia-modprobe'
    )
  else
    NVIDIA_KERNEL_PACKAGES=(
      "akmod-nvidia${DRIVER_SUFFIX}"
      'nvidia-modprobe'
    )
    DNF_DEFINE_ARGS=(--setopt="excludepkgs=akmod-nvidia-open*,kmod-nvidia-open*")
  fi

  dnf install \
      --assumeyes \
      --setopt=install_weak_deps=False \
      ${KERNEL_DEVEL_VERSION}

  dnf install \
      --assumeyes \
      --setopt=install_weak_deps=False \
      --exclude=${AKMOD_PACKAGES_EXCLUDE} \
      ${AKMOD_PACKAGES[@]}

  cp '/usr/sbin/akmodsbuild' \
     '/usr/sbin/akmodsbuild.backup'

  sed --in-place \
      '/if \[\[ -w \/var \]\] ; then/,/fi/d' \
      '/usr/sbin/akmodsbuild'

  dnf install \
      --assumeyes \
      --setopt=install_weak_deps=False \
      ${DNF_DEFINE_ARGS[@]} \
      ${NVIDIA_KERNEL_PACKAGES[@]}

  mv '/usr/sbin/akmodsbuild.backup' \
     '/usr/sbin/akmodsbuild'

  if [[ "$IMAGE_NAME" != *'nvidia-open'* ]]; then
    echo "Enforcing proprietary compilation path targets..."
  
    # 1. Block the fallback macro globally for the akmods compilation engine
    mkdir -p /etc/rpm
    echo "%_without_kmod_nvidia_detect 1" > /etc/rpm/macros.nvidia-kmod

    # 2. Hardcode the kernel profile target configuration
    mkdir -p /etc/nvidia
    echo "CONFIG_NVIDIA_KERNEL=kernel" > /etc/nvidia/kernel.conf
  fi
    
  echo 'Installing kmod...'
  akmods --force \
         --kernels ${KERNEL_VERSION} \
         --kmod 'nvidia'
  
  # Depends on word splitting
  # shellcheck disable=SC2086
  modinfo /usr/lib/modules/${KERNEL_VERSION}/extra/nvidia/nvidia{,-drm,-modeset,-peermem,-uvm}.ko.xz \
          > '/dev/null' \
    || (cat "/var/cache/akmods/nvidia/*.failed.log" && exit 1)
  
  # View license information
  # Depends on word splitting
  # shellcheck disable=SC2086
  modinfo --license \
          /usr/lib/modules/${KERNEL_VERSION}/extra/nvidia/nvidia{,-drm,-modeset,-peermem,-uvm}.ko.xz
  
  # If the script is in the same directory, it can be called on directly.
  chmod +x ./sign-modules.sh
  ./sign-modules.sh 'nvidia'
}

install-nvidia-container-toolkit() {
  NVIDIA_CONTAINER_TOOLKIT_REPOSITORY='https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo'
  echo "Installing nvidia-container-toolkit from ${NVIDIA_CONTAINER_TOOLKIT_REPOSITORY}"
  curl --location \
       ${NVIDIA_CONTAINER_TOOLKIT_REPOSITORY} \
      --output '/etc/yum.repos.d/nvidia-container-toolkit.repo'
  sed --in-place \
      's/^gpgcheck=0/gpgcheck=1/' \
      '/etc/yum.repos.d/nvidia-container-toolkit.repo'
  sed --in-place \
      's/^enabled=0.*/enabled=1/' \
      '/etc/yum.repos.d/nvidia-container-toolkit.repo'
  dnf install \
      --assumeyes \
      --setopt=install_weak_deps=False \
      'nvidia-container-toolkit'
}

install-nvidia-selinux-policy() {
  NVIDIA_CONTAINER_SELINUX_POLICY='https://raw.githubusercontent.com/NVIDIA/dgx-selinux/master/bin/RHEL9/nvidia-container.pp'
  echo "Installing Nvidia SELinux Policy from ${NVIDIA_CONTAINER_SELINUX_POLICY}"
  curl --location \
       ${NVIDIA_CONTAINER_SELINUX_POLICY} \
      -o 'nvidia-container.pp'
  semodule --install='nvidia-container.pp'
}

install-packages() {
  dnf install \
      --assumeyes \
      --setopt=install_weak_deps=False \
      ${NVIDIA_PACKAGES_LIST[@]}
}

cleanup() {
  dnf remove \
      --assumeyes \
      ${PACKAGES_CLEANUP[@]}
  rm -f ${FILES_CLEANUP[@]}
}

initial-setup
install-rpmfusion
install-kernel-modules-43
install-nvidia-container-toolkit
install-nvidia-selinux-policy
install-packages
cleanup
