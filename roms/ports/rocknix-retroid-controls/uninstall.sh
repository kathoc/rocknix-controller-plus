#!/bin/bash

set -u

base_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
payload="${base_dir}/payload"
state_dir=/storage/.config/retroid-controls
log_file=/storage/retroid-controls-uninstall.log
features=/storage/.config/emulationstation/es_features.cfg
systems=/storage/.config/emulationstation/es_systems.cfg
settings=/storage/.config/system/configs/system.cfg
sway_config=/storage/.config/sway/config

mkdir -p /storage
exec > >(tee -a "${log_file}") 2>&1

fail() {
  echo
  echo "ERROR: $*"
  echo "Log: ${log_file}"
  echo
  echo "This window will close in 20 seconds."
  sleep 20
  exit 1
}

echo "=========================================="
echo " Retroid Controls uninstaller for ROCKNIX"
echo "=========================================="
echo

[ "$(id -u)" = 0 ] || fail "This uninstaller must run from the ROCKNIX menu."
[ -x "${payload}/config-tools/remove-retroid-config.py" ] || \
  fail "The uninstaller payload is missing. Copy the complete package."

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="${state_dir}/uninstall-backups/${stamp}"
mkdir -p "${backup_dir}" || fail "Could not create the uninstall backup."

echo "[1/6] Backing up the current configuration..."
for file in "${features}" "${systems}" "${settings}" "${sway_config}"; do
  if [ -e "${file}" ]; then
    cp -a "${file}" "${backup_dir}/$(basename "${file}")" || \
      fail "Could not back up ${file}."
  fi
done

echo "[2/6] Removing EmulationStation and Sway additions..."
work_dir="$(mktemp -d /tmp/retroid-controls-remove.XXXXXX)" || \
  fail "Could not create a temporary directory."
work_features="${work_dir}/es_features.cfg"
work_systems="${work_dir}/es_systems.cfg"
work_settings="${work_dir}/system.cfg"
work_sway="${work_dir}/sway-config"
cleanup_work() {
  rm -f "${work_features}" "${work_systems}" "${work_settings}" "${work_sway}"
  rmdir "${work_dir}" 2>/dev/null || true
}
trap cleanup_work EXIT

for pair in \
    "${features}:${work_features}" \
    "${systems}:${work_systems}" \
    "${settings}:${work_settings}" \
    "${sway_config}:${work_sway}"; do
  source_file="${pair%%:*}"
  target_file="${pair#*:}"
  [ -r "${source_file}" ] || fail "Required configuration is missing: ${source_file}"
  cp "${source_file}" "${target_file}" || fail "Could not prepare ${source_file}."
done

python3 "${payload}/config-tools/remove-retroid-config.py" \
  --features "${work_features}" \
  --systems "${work_systems}" \
  --settings "${work_settings}" \
  --sway "${work_sway}" || fail "Could not remove the managed configuration."

python3 - "${work_features}" "${work_systems}" <<'PY' || \
  fail "The cleaned EmulationStation configuration failed validation."
import sys
import xml.etree.ElementTree as ET
for path in sys.argv[1:]:
    ET.parse(path)
PY

install -m 644 "${work_features}" "${features}"
install -m 644 "${work_systems}" "${systems}"
install -m 644 "${work_settings}" "${settings}"
install -m 644 "${work_sway}" "${sway_config}"

echo "[3/6] Stopping installed helper services..."
for service in \
    retroid-charge-awake.service \
    retroid-touchpad-activate.service \
    retroid-touchpad-config.service \
    retroid-inputplumber-config.service \
    retroid-controls-config.service; do
  systemctl stop "${service}" >/dev/null 2>&1 || true
done

target=/usr/share/inputplumber/devices/02-mangmi-pocket-max.yaml
while awk -v target="${target}" '
  $5 == target && $4 ~ /^\/.config\/touchpad\// { found=1 }
  END { exit !found }
' /proc/self/mountinfo; do
  umount "${target}" || fail "Could not restore the stock InputPlumber profile."
done
target=/usr/share/inputplumber/capability_maps/retroid_mcu.yaml
while awk -v target="${target}" '
  $5 == target && $4 ~ /^\/.config\/input-controls\// { found=1 }
  END { exit !found }
' /proc/self/mountinfo; do
  umount "${target}" || fail "Could not restore the stock Retroid capability map."
done

echo "[4/6] Removing boot-time integration..."
for service in \
    retroid-charge-awake.service \
    retroid-touchpad-activate.service \
    retroid-touchpad-config.service \
    retroid-inputplumber-config.service \
    retroid-controls-config.service; do
  rm -f \
    "/storage/.config/system.d/${service}" \
    "/storage/.config/system.d/multi-user.target.wants/${service}"
done
rm -f /storage/.config/system.d/inputplumber.service.d/90-retroid-controls.conf
rmdir /storage/.config/system.d/inputplumber.service.d 2>/dev/null || true
rm -f /run/systemd/system/inputplumber.service.d/90-retroid-controls.conf
rmdir /run/systemd/system/inputplumber.service.d 2>/dev/null || true
rm -f /storage/.config/logind.conf.d/90-retroid-charge-awake.conf
systemctl daemon-reload || fail "systemd could not reload its configuration."
systemctl reload systemd-logind.service >/dev/null 2>&1 || \
  fail "systemd-logind could not restore its standard power-key behavior."

echo "[5/6] Removing installed files..."
for file in "${payload}"/input-controls/*; do
  [ -f "${file}" ] || continue
  rm -f "/storage/.config/input-controls/$(basename "${file}")"
done
rm -f /storage/.config/input-controls/retroid-gamepad-proxy.py
for file in "${payload}"/touchpad/*; do
  [ -f "${file}" ] || continue
  rm -f "/storage/.config/touchpad/$(basename "${file}")"
done
for file in "${payload}"/config-tools/*.py; do
  rm -f "${state_dir}/tools/$(basename "${file}")"
done
rm -f \
  "${state_dir}/apply-config.sh" \
  "${state_dir}/retroid-controls-config.service" \
  "${state_dir}/charge-awake.sh" \
  "${state_dir}/retroid-charge-awake.service"
rmdir /storage/.config/input-controls /storage/.config/touchpad \
  "${state_dir}/tools" 2>/dev/null || true

echo "[6/6] Staging the stock input services for reboot..."
swaymsg reload >/dev/null 2>&1 || true

sync
echo
echo "UNINSTALLATION COMPLETE"
echo "Backup: ${backup_dir}"
echo "Log:    ${log_file}"
echo
echo "The installer files remain in Ports so the features can be installed again."
echo "The device will reboot in 8 seconds to restore the stock input driver."
( sleep 8; systemctl reboot ) >/dev/null 2>&1 &
sleep 6
exit 0
