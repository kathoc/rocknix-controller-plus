#!/bin/bash
set -eu

target_file=/usr/share/inputplumber/devices/02-mangmi-pocket-max.yaml
source_root="$(awk -v target="$target_file" '
  $5 == target { source=$4 }
  END { print source }
' /proc/self/mountinfo)"

case "$source_root" in
  *touchscreen-orientation-*)
    profile=/storage/.config/touchpad/touchscreen-profile.yaml
    composite_name="Retroid Direct Touchscreen"
    ;;
  *)
    profile=/storage/.config/touchpad/touchpad-profile.yaml
    composite_name="Retroid Touchscreen Trackpad"
    ;;
esac

for _ in $(seq 1 50); do
  device_id="$(inputplumber devices list 2>/dev/null | awk -F '│' '
    index($0, name) {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' name="$composite_name")"
  if [ -n "$device_id" ]; then
    inputplumber device "$device_id" profile load "$profile"
    exit 0
  fi
  sleep 0.2
done

echo "Retroid touch device was not created" >&2
exit 1
