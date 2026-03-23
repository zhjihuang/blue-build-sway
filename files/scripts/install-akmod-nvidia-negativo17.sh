#!/usr/bin/env bash

# Copyright 2025 Universal Blue
# Copyright 2025 The Secureblue Authors
# Copyright 2025 The BlueBuild Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

set -oue pipefail

mkdir -p "/var/tmp"
chmod 1777 "/var/tmp"

# -------------------------------- 
# Repository Setup
# ================================
if [[ "$IMAGE_NAME" == *'surface'* ]]; then
  KERNEL_NAME='kernel-surface'
  KERNEL_DEVEL_NAME='kernel-surface-devel'
  DRIVER_VERSION='580'
else
  KERNEL_NAME='kernel'
  KERNEL_DEVEL_NAME='kernel-devel-matched'
  DRIVER_VERSION='580'
fi
KERNEL_VERSION="$(rpm -q ${KERNEL_NAME} --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
RELEASE="$(rpm -E '%fedora.%_arch')"

if [[ "$IMAGE_NAME" == *'nvidia-open'* ]]; then
  curl --fail \
       --location \
       --silent \
       --show-error \
       --retry 5 \
       -o '/etc/yum.repos.d/negativo17-fedora-nvidia.repo' \
       'https://negativo17.org/repos/fedora-nvidia.repo'
  sed --in-place \
      '/^enabled=1/a\priority=90' \
      '/etc/yum.repos.d/negativo17-fedora-nvidia.repo'
else
  curl --fail \
       --location \
       --silent \
       --show-error \
       --retry 5 \
       -o "/etc/yum.repos.d/fedora-nvidia-${DRIVER_VERSION}.repo" \
       'https://negativo17.org/repos/fedora-nvidia-580.repo'
  sed --in-place \
      '/^enabled=1/a\priority=90' \
      "/etc/yum.repos.d/fedora-nvidia-${DRIVER_VERSION}.repo"
  if [ -f '/etc/yum.repos.d/fedora-multimedia.repo' ]; then
    sed --in-place \
        's/^enabled=.*/enabled=0/' \
        '/etc/yum.repos.d/fedora-multimedia.repo'
  fi
fi

# -------------------------------- 
# Kernel module
# ================================
KERNEL_DEVEL_VERSION="${KERNEL_DEVEL_NAME}-$(rpm -q ${KERNEL_NAME} --queryformat '%{VERSION}')"
AKMOD_PACKAGES_EXCLUDE='kernel-core,kernel-devel,kernel-devel-matched,kernel-modules-core'
AKMOD_PACKAGES=(
  'akmods'
  'gcc-c++'
)
NVIDIA_PACKAGES=(
  'nvidia-kmod-common'
  'nvidia-modprobe'
)

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

# TODO remove this when fixed upstream
sed --in-place \
    '/if \[\[ -w \/var \]\] ; then/,/fi/d' \
    '/usr/sbin/akmodsbuild'

dnf install \
    --assumeyes \
    --setopt=install_weak_deps=False \
    ${NVIDIA_PACKAGES[@]}
mv '/usr/sbin/akmodsbuild.backup' \
   '/usr/sbin/akmodsbuild'

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
chmod +x \
      ./sign-modules.sh
./sign-modules.sh 'nvidia'

# -------------------------------- 
# Extra packages
# ================================ 
NVIDIA_CONTAINER_TOOLKIT_REPOSITORY='https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo'
NVIDIA_CONTAINER_SELINUX_POLICY='https://raw.githubusercontent.com/NVIDIA/dgx-selinux/master/bin/RHEL9/nvidia-container.pp'
NVIDIA_PACKAGES_LIST=(
  'nvidia-driver'
  'nvidia-persistenced'
  'nvidia-settings'
  'nvidia-driver-cuda'
  'nvidia-container-toolkit'
  'libnvidia-fbc'
  'libva-nvidia-driver'
)

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
    ${NVIDIA_PACKAGES_LIST[@]}
curl --location \
     ${NVIDIA_CONTAINER_SELINUX_POLICY} \
    -o 'nvidia-container.pp'
semodule --install='nvidia-container.pp'

# -------------------------------- 
# Cleanup
# ================================
if [[ "$IMAGE_NAME" == *'surface'* ]]; then
  PACKAGES_CLEANUP_KERNEL=(
    'kernel-devel'
    'kernel-headers'
    'surface-kernel-devel'
  )
else
  PACKAGES_CLEANUP_KERNEL=(
    'kernel-devel'
    'kernel-headers'
  )
fi
PACKAGES_CLEANUP=(
  'akmod-nvidia'
  'akmods'
  ${PACKAGES_CLEANUP_KERNEL[@]}
)

dnf remove \
    --assumeyes \
    ${PACKAGES_CLEANUP[@]}

if [ -f '/etc/yum.repos.d/fedora-multimedia.repo' ]; then
  sed --in-place \
      's/^enabled=.*/enabled=1/' \
      '/etc/yum.repos.d/fedora-multimedia.repo'
fi

rm -f 'nvidia-container.pp'
rm -f '/etc/yum.repos.d/nvidia-container-toolkit.repo'
rm -f "/etc/yum.repos.d/fedora-nvidia-${DRIVER_VERSION}.repo"
rm -f '/etc/yum.repos.d/negativo17-fedora-nvidia.repo'
