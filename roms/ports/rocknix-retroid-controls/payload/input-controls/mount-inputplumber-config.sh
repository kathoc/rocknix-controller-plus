#!/bin/bash
set -eu

source_file=/storage/.config/input-controls/retroid_mcu.yaml
target_file=/usr/share/inputplumber/capability_maps/retroid_mcu.yaml

if ! awk -v target="${target_file}" '$5 == target { found=1 } END { exit !found }' \
    /proc/self/mountinfo; then
  mount --bind "${source_file}" "${target_file}"
fi
