#!/bin/bash
set -eu

mode=mouse
if [ "${1:-}" = "mouse" ] || [ "${1:-}" = "trackball" ] || [ "${1:-}" = "touch" ]; then
  mode="$1"
  shift
fi

# RetroArch rotation is expressed as clockwise quarter turns (0..3). The RP5
# panel's native touch coordinates are already one clockwise turn away from the
# landscape display, so normal operation starts with the inverse (left) turn.
case "${1:-0}" in
  0|none|false|'') orientation=left ;;
  1|90)            orientation=normal ;;
  2|180)           orientation=right ;;
  3|270)           orientation=upsidedown ;;
  *)               orientation=left ;;
esac

if [ "$mode" = "touch" ]; then
  source_file="/storage/.config/touchpad/touchscreen-orientation-${orientation}.yaml"
  composite_name="Retroid Direct Touchscreen"
  profile=/storage/.config/touchpad/touchscreen-profile.yaml
else
  source_file="/storage/.config/touchpad/trackpad-orientation-${orientation}.yaml"
  composite_name="Retroid Touchscreen Trackpad"
  profile=/storage/.config/touchpad/touchpad-profile.yaml
fi
target_file=/usr/share/inputplumber/devices/02-mangmi-pocket-max.yaml
source_root="${source_file#/storage}"
current_source="$(awk -v target="$target_file" '
  $5 == target { source=$4 }
  END { print source }
' /proc/self/mountinfo)"

[ "$current_source" != "$source_root" ] || exit 0

while awk -v target="$target_file" '$5 == target { found=1 } END { exit !found }' \
  /proc/self/mountinfo; do
  umount "$target_file"
done
mount --bind "$source_file" "$target_file"
systemctl restart inputplumber.service

for _ in $(seq 1 50); do
  device_id="$(inputplumber devices list 2>/dev/null | awk -F '│' '
    index($0, name) {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' name="$composite_name")"
  if [ -n "$device_id" ]; then
    inputplumber device "$device_id" profile load "$profile" >/dev/null
    exit 0
  fi
  sleep 0.2
done

echo "Retroid touchscreen trackpad device was not recreated" >&2
exit 1
