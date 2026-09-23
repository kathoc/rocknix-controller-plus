#!/bin/bash

set -u

. /etc/profile

controls_dir=/storage/.config/input-controls
config_file=/tmp/retroid-gamepad-controls.json
profile_file=/tmp/retroid-gamepad-profile.yaml
previous_profile=/tmp/retroid-gamepad-previous-profile.yaml
profile_saved=false
osd_pid=""
osd_context=/tmp/retroid-game-osd-context.json
osd_log=/tmp/retroid-game-osd.log
touchpad_dir=/storage/.config/touchpad
touch_trackball_pid=""
gamepad_id=""

arguments="$*"
platform="${arguments##*-P}"
platform="${platform%% *}"
rom_path="$1"
rom_name="${rom_path##*/}"

setting() {
  get_setting "$1" "${platform}" "${rom_name}"
}

find_gamepad_id() {
  inputplumber devices list 2>/dev/null | awk -F '│' '
    index($0, "Retroid Layout") {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  '
}

a_raw="$(setting 'Aボタン設定')"
b_raw="$(setting 'Bボタン設定')"
x_raw="$(setting 'Xボタン設定')"
y_raw="$(setting 'Yボタン設定')"
l1_raw="$(setting 'L1ボタン設定')"
l2_raw="$(setting 'L2ボタン設定')"
r1_raw="$(setting 'R1ボタン設定')"
r2_raw="$(setting 'R2ボタン設定')"
direction_raw="$(setting '方向入力モード')"
stick_mode_raw="$(setting '左スティック入力')"

# Do not replace the normal InputPlumber controller for games with no saved
# control override. This keeps the stock input path (including rumble) intact.
custom_controls=false
for value in "${a_raw}" "${b_raw}" "${x_raw}" "${y_raw}" \
    "${l1_raw}" "${l2_raw}" "${r1_raw}" "${r2_raw}" "${direction_raw}"; do
  if [ -n "${value}" ]; then
    custom_controls=true
    break
  fi
done
[ "${stick_mode_raw}" != dpad ] || custom_controls=true

a_setting="${a_raw:-normal:a}"
b_setting="${b_raw:-normal:b}"
x_setting="${x_raw:-normal:x}"
y_setting="${y_raw:-normal:y}"
l1_setting="${l1_raw:-normal:l1}"
l2_setting="${l2_raw:-normal:l2}"
r1_setting="${r1_raw:-normal:r1}"
r2_setting="${r2_raw:-normal:r2}"
direction_mode="${direction_raw:-8way}"
stick_mode="${stick_mode_raw:-native}"

turbo_speed="$(setting 'TURBO速度')"
repeat_delay_setting="$(setting 'REPEAT開始待ち')"
repeat_speed="$(setting 'REPEAT速度')"

# Mouse and trackball modes grab the existing virtual touchscreen and transform
# it in userspace. InputPlumber is never restarted during game launch.
if [ "${platform}" = "arcade" ]; then
  screen_rotation="$(setting rotation)"
  tate_mode="$(setting tatemode)"
  touch_mode="$(setting 'タッチ操作モード')"
  movement="$(setting 'マウス移動量')"
  inertia="$(setting 'トラックボール慣性速度')"
  if [ -z "${screen_rotation}" ] && [ "${tate_mode}" = "1" ]; then
    screen_rotation=1
  fi
  [ -n "${screen_rotation}" ] || screen_rotation=0
  [ -n "${touch_mode}" ] || touch_mode=mouse
  [ -n "${movement}" ] || movement=100
  [ -n "${inertia}" ] || inertia=100
  # The old scale topped out at 300%. On the new scale that same reference
  # speed is 100%, while 200% is twice as fast. Preserve an old saved 300%.
  [ "${movement}" != 300 ] || movement=100
  case "${movement}" in
    10|20|25|30|40|50|60|70|75|80|90|100|110|120|125|130|140|150|160|170|180|190|200) ;;
    *) movement=100 ;;
  esac
  if [ "${touch_mode}" = "mouse" ]; then
    # Sway/libinput caps accel_speed at 1.0, so it cannot represent values
    # above the former 300% setting. Use the relative-motion helper without
    # inertia and make new 100% equal to that former maximum.
    mouse_movement=$((movement * 3))
    "${touchpad_dir}/retroid-trackball.py" \
      --movement "${mouse_movement}" --inertia 0 --rotation "${screen_rotation}" \
      >/tmp/retroid-mouse.log 2>&1 &
    touch_trackball_pid=$!
  elif [ "${touch_mode}" = "trackball" ]; then
    "${touchpad_dir}/retroid-trackball.py" \
      --movement "${movement}" --inertia "${inertia}" --rotation "${screen_rotation}" \
      >/tmp/retroid-trackball.log 2>&1 &
    touch_trackball_pid=$!
  elif [ "${touch_mode}" = "touch" ] && [ "${screen_rotation}" != "0" ]; then
    "${touchpad_dir}/retroid-touchscreen-proxy.py" \
      --rotation "${screen_rotation}" >/tmp/retroid-touchscreen.log 2>&1 &
    touch_trackball_pid=$!
  fi
fi

case "${turbo_speed}" in
  slow) turbo_hz=6 ;;
  fast) turbo_hz=15 ;;
  max) turbo_hz=30 ;;
  *) turbo_hz=10 ;;
esac
case "${repeat_delay_setting}" in
  short) repeat_delay=0.25 ;;
  long) repeat_delay=0.70 ;;
  *) repeat_delay=0.45 ;;
esac
case "${repeat_speed}" in
  slow) repeat_hz=6 ;;
  fast) repeat_hz=15 ;;
  max) repeat_hz=30 ;;
  *) repeat_hz=10 ;;
esac

printf '%s\n' \
  '{' \
  '  "buttons": {' \
  "    \"a\": \"${a_setting}\"," \
  "    \"b\": \"${b_setting}\"," \
  "    \"x\": \"${x_setting}\"," \
  "    \"y\": \"${y_setting}\"," \
  "    \"l1\": \"${l1_setting}\"," \
  "    \"l2\": \"${l2_setting}\"," \
  "    \"r1\": \"${r1_setting}\"," \
  "    \"r2\": \"${r2_setting}\"" \
  '  },' \
  "  \"direction_mode\": \"${direction_mode}\"," \
  "  \"stick_mode\": \"${stick_mode}\"," \
  "  \"turbo_hz\": ${turbo_hz}," \
  "  \"repeat_delay\": ${repeat_delay}," \
  "  \"repeat_hz\": ${repeat_hz}" \
  '}' > "${config_file}"

cleanup() {
  if [ -n "${osd_pid}" ]; then
    kill "${osd_pid}" >/dev/null 2>&1 || true
    wait "${osd_pid}" 2>/dev/null || true
  fi
  if [ -n "${touch_trackball_pid}" ]; then
    kill "${touch_trackball_pid}" >/dev/null 2>&1 || true
    wait "${touch_trackball_pid}" 2>/dev/null || true
  fi
  if [ "${profile_saved}" = true ] && [ -s "${previous_profile}" ]; then
    inputplumber device "${gamepad_id}" profile load "${previous_profile}" >/dev/null 2>&1 || true
  fi
  rm -f "${config_file}" "${profile_file}" "${previous_profile}" "${osd_context}"
}
trap cleanup EXIT HUP INT TERM

# Keep InputPlumber and its normal DualSense target alive. Per-game overrides
# are now applied as a native profile, preserving rumble and analog reports.
for _ in $(seq 1 50); do
  gamepad_id="$(find_gamepad_id)"
  [ -z "${gamepad_id}" ] || break
  sleep 0.1
done
if [ -n "${gamepad_id}" ] && \
    inputplumber device "${gamepad_id}" profile dump >"${previous_profile}" 2>/dev/null; then
  profile_saved=true
fi
if [ "${custom_controls}" = true ] && [ -n "${gamepad_id}" ]; then
  if "${controls_dir}/generate-inputplumber-profile.py" \
        --config "${config_file}" --output "${profile_file}" && \
      inputplumber device "${gamepad_id}" profile load "${profile_file}" >/dev/null 2>&1; then
    :
  fi
fi

# Start the in-game settings OSD after the final controller device exists.
# Empty settings are omitted so installing the package never creates defaults.
python3 - "${osd_context}" "${platform}" "${rom_name}" "${config_file}" \
  "${profile_file}" "${gamepad_id}" \
  "${a_raw}" "${b_raw}" "${x_raw}" "${y_raw}" \
  "${l1_raw}" "${l2_raw}" "${r1_raw}" "${r2_raw}" \
  "${direction_raw}" "${stick_mode_raw}" "${turbo_speed}" \
  "${repeat_delay_setting}" "${repeat_speed}" \
  "${touch_mode:-}" "${movement:-}" "${inertia:-}" <<'PY'
import json, sys
path, platform, rom_name, config_file, profile_file, gamepad_id, *values = sys.argv[1:]
names = [
    "Aボタン設定", "Bボタン設定", "Xボタン設定", "Yボタン設定",
    "L1ボタン設定", "L2ボタン設定", "R1ボタン設定", "R2ボタン設定",
    "方向入力モード", "左スティック入力", "TURBO速度", "REPEAT開始待ち",
    "REPEAT速度", "タッチ操作モード", "マウス移動量", "トラックボール慣性速度",
]
context = {
    "platform": platform,
    "rom_name": rom_name,
    "config_file": config_file,
    "profile_file": profile_file,
    "gamepad_id": gamepad_id,
    "settings": {name: value for name, value in zip(names, values) if value},
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(context, handle, ensure_ascii=False)
PY
"${controls_dir}/retroid-game-osd.py" --context "${osd_context}" \
  >"${osd_log}" 2>&1 &
osd_pid=$!

/usr/bin/runemu.sh "$@"
exit_code=$?
exit "${exit_code}"
