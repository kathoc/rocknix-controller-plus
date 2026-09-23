#!/bin/bash
set -eu

# ES-DE uses direct touch. Per-game launch code switches to mouse/trackball
# only when the selected game asks for it.
source_file=/storage/.config/touchpad/touchscreen-orientation-left.yaml
target_file=/usr/share/inputplumber/devices/02-mangmi-pocket-max.yaml

source_root="${source_file#/storage}"
current_source="$(awk -v target="$target_file" '
  $5 == target { source=$4 }
  END { print source }
' /proc/self/mountinfo)"
if [ "$current_source" != "$source_root" ]; then
  while awk -v target="$target_file" '$5 == target { found=1 } END { exit !found }' \
    /proc/self/mountinfo; do
    umount "$target_file"
  done
  mount --bind "$source_file" "$target_file"
fi
