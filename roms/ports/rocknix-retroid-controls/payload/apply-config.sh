#!/bin/bash

set -eu

state_dir=/storage/.config/retroid-controls
tools_dir="${state_dir}/tools"
es_dir=/storage/.config/emulationstation
features="${es_dir}/es_features.cfg"
systems="${es_dir}/es_systems.cfg"
sway_config=/storage/.config/sway/config
force=false
[ "${1:-}" = "--force" ] && force=true

[ -r "${features}" ]
[ -r "${systems}" ]

# Native analog is the safe global default. ROCKNIX's stock value of 1 makes
# the left stick emit D-pad input too, which conflicts with analog controls.
# Digital-only games can opt back in through 左スティック入力.
. /etc/profile
if ! grep -qx 'global\.analogue=0' "${J_CONF}"; then
  set_setting global.analogue 0
fi

work_dir="$(mktemp -d /tmp/retroid-controls-apply.XXXXXX)"
work_features="${work_dir}/es_features.cfg"
work_systems="${work_dir}/es_systems.cfg"
work_sway="${work_dir}/sway-config"
cleanup() {
  rm -f "${work_features}" "${work_systems}" "${work_sway}"
  rmdir "${work_dir}" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

cp "${features}" "${work_features}"
cp "${systems}" "${work_systems}"

need_features=false
for name in 'Aボタン設定' 'R2ボタン設定' '方向入力モード' '左スティック入力' 'TURBO速度' 'REPEAT速度' \
    'タッチ操作モード' 'トラックボール慣性速度'; do
  if ! grep -q "${name}" "${features}"; then
    need_features=true
    break
  fi
done

if [ "${force}" = true ] || [ "${need_features}" = true ]; then
  python3 "${tools_dir}/add-global-input-features.py" "${work_features}"
  python3 "${tools_dir}/add-arcade-touch-features.py" "${work_features}"
fi

if [ "${force}" = true ] || \
    grep -q '<command>/usr/bin/runemu.sh ' "${systems}" || \
    grep -q '<command>/storage/.config/arcade-controls/run-arcade.sh ' "${systems}"; then
  python3 "${tools_dir}/patch-es-systems.py" "${work_systems}"
fi

mkdir -p "$(dirname "${sway_config}")"
if [ -r "${sway_config}" ]; then
  cp "${sway_config}" "${work_sway}"
elif [ -r /usr/config/sway/config ]; then
  cp /usr/config/sway/config "${work_sway}"
else
  touch "${work_sway}"
fi
python3 "${tools_dir}/patch-sway-config.py" "${work_sway}"

# Validate every generated file before replacing the live configuration.
python3 - "${work_features}" "${work_systems}" <<'PY'
import sys
import xml.etree.ElementTree as ET
for path in sys.argv[1:]:
    ET.parse(path)
PY

cmp -s "${work_features}" "${features}" || install -m 644 "${work_features}" "${features}"
cmp -s "${work_systems}" "${systems}" || install -m 644 "${work_systems}" "${systems}"
if [ ! -e "${sway_config}" ] || ! cmp -s "${work_sway}" "${sway_config}"; then
  install -m 644 "${work_sway}" "${sway_config}"
fi

# sway.sh may generate its per-device configuration during startup. This
# service deliberately runs after sway.service, then reloads the compositor so
# the HOME+Back binding and touch-device rules are active on the same boot.
for attempt in $(seq 1 50); do
  for socket in /run/0-runtime-dir/sway-ipc.*.sock /var/run/0-runtime-dir/sway-ipc.*.sock; do
    [ -S "${socket}" ] || continue
    swaymsg -s "${socket}" reload >/dev/null 2>&1 || true
    exit 0
  done
  sleep 0.1
done
