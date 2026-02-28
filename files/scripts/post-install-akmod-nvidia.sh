#!/usr/bin/bash

set -ouex pipefail

cp '/usr/lib/modprobe.d/nvidia-modeset.conf' '/etc/modprobe.d/nvidia-modeset.conf'
sed --in-place 's/omit_drivers/force_drivers/g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
sed --in-place 's/ nvidia / i915 amdgpu nvidia /g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
