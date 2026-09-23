#!/bin/bash

set -u

base_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
payload="${base_dir}/payload"
state_dir=/storage/.config/retroid-controls
backup_root="${state_dir}/backups"
log_file=/storage/retroid-controls-install.log

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
echo " Retroid Controls installer for ROCKNIX"
echo "=========================================="
echo

[ "$(id -u)" = 0 ] || fail "This installer must run from the ROCKNIX menu."
[ -d "${payload}" ] || fail "The payload directory is missing. Copy the complete package."

# ROCKNIX exposes these variables from /etc/profile.
. /etc/profile
case "${QUIRK_DEVICE:-}" in
  "Retroid Pocket 5") ;;
  *) fail "Unsupported device: ${QUIRK_DEVICE:-unknown}. This package is for Retroid Pocket 5." ;;
esac
[ -e /usr/share/inputplumber/devices/02-mangmi-pocket-max.yaml ] || \
  fail "The required InputPlumber mount target does not exist on this ROCKNIX build."

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="${backup_root}/${stamp}"
mkdir -p "${backup_dir}" || fail "Could not create the backup directory."

echo "[1/6] Backing up the current configuration..."
for file in \
    /storage/.config/emulationstation/es_features.cfg \
    /storage/.config/emulationstation/es_systems.cfg \
    /storage/.config/system/configs/system.cfg \
    /storage/.config/sway/config; do
  if [ -e "${file}" ]; then
    cp -a "${file}" "${backup_dir}/$(basename "${file}")" || \
      fail "Could not back up ${file}."
  fi
done

echo "[2/6] Installing controller and touchscreen components..."
mkdir -p \
  /storage/.config/input-controls \
  /storage/.config/touchpad \
  "${state_dir}/tools" \
  /storage/.config/logind.conf.d \
  /storage/.config/system.d/inputplumber.service.d \
  /storage/.config/system.d/multi-user.target.wants || \
  fail "Could not create installation directories."

for file in "${payload}"/input-controls/*; do
  [ -f "${file}" ] || continue
  case "${file}" in
    *.sh|*.py|*/inputplumber-rp5) mode=755 ;;
    *) mode=644 ;;
  esac
  install -m "${mode}" "${file}" \
    "/storage/.config/input-controls/$(basename "${file}")" || \
    fail "Could not install $(basename "${file}")."
done
# Remove the superseded userspace virtual-gamepad implementation from older builds.
rm -f /storage/.config/input-controls/retroid-gamepad-proxy.py
[ -x /storage/.config/input-controls/inputplumber-rp5 ] || \
  fail "The native RP5 InputPlumber binary is missing."
install -m 644 "${payload}/input-controls/inputplumber-rp5.service.conf" \
  /storage/.config/system.d/inputplumber.service.d/90-retroid-controls.conf || \
  fail "Could not install the InputPlumber service override."
# Remove the temporary runtime override used by pre-installer test builds.
rm -f /run/systemd/system/inputplumber.service.d/90-retroid-controls.conf
rmdir /run/systemd/system/inputplumber.service.d 2>/dev/null || true

for file in "${payload}"/touchpad/*; do
  [ -f "${file}" ] || continue
  case "${file}" in
    *.sh|*.py) mode=755 ;;
    *) mode=644 ;;
  esac
  install -m "${mode}" "${file}" "/storage/.config/touchpad/$(basename "${file}")" || \
    fail "Could not install $(basename "${file}")."
done

for file in "${payload}"/config-tools/*.py; do
  install -m 755 "${file}" "${state_dir}/tools/$(basename "${file}")" || \
    fail "Could not install $(basename "${file}")."
done
install -m 755 "${payload}/apply-config.sh" "${state_dir}/apply-config.sh" || \
  fail "Could not install apply-config.sh."
install -m 644 "${payload}/retroid-controls-config.service" \
  "${state_dir}/retroid-controls-config.service" || \
  fail "Could not install the persistent configuration service."
install -m 755 "${payload}/power/retroid-charge-awake.sh" \
  "${state_dir}/charge-awake.sh" || \
  fail "Could not install the charging sleep inhibitor."
install -m 644 "${payload}/power/retroid-charge-awake.service" \
  "${state_dir}/retroid-charge-awake.service" || \
  fail "Could not install the charging sleep inhibitor service."
install -m 644 "${payload}/power/90-retroid-charge-awake.conf" \
  /storage/.config/logind.conf.d/90-retroid-charge-awake.conf || \
  fail "Could not install the power-key exception."

echo "[3/6] Enabling boot-time services..."
ln -sfn "${state_dir}/retroid-controls-config.service" \
  /storage/.config/system.d/retroid-controls-config.service
ln -sfn "${state_dir}/retroid-controls-config.service" \
  /storage/.config/system.d/multi-user.target.wants/retroid-controls-config.service
ln -sfn "${state_dir}/retroid-charge-awake.service" \
  /storage/.config/system.d/retroid-charge-awake.service
ln -sfn "${state_dir}/retroid-charge-awake.service" \
  /storage/.config/system.d/multi-user.target.wants/retroid-charge-awake.service
for service in retroid-touchpad-config.service retroid-touchpad-activate.service; do
  ln -sfn "/storage/.config/touchpad/${service}" "/storage/.config/system.d/${service}"
  ln -sfn "/storage/.config/touchpad/${service}" \
    "/storage/.config/system.d/multi-user.target.wants/${service}"
done
ln -sfn /storage/.config/input-controls/retroid-inputplumber-config.service \
  /storage/.config/system.d/retroid-inputplumber-config.service
ln -sfn /storage/.config/input-controls/retroid-inputplumber-config.service \
  /storage/.config/system.d/multi-user.target.wants/retroid-inputplumber-config.service
systemctl daemon-reload || fail "systemd could not reload the installed services."
systemctl reload systemd-logind.service >/dev/null 2>&1 || \
  fail "systemd-logind could not reload the power-key setting."

echo "[4/6] Adding per-game settings to EmulationStation..."
"${state_dir}/apply-config.sh" --force || fail "Could not patch the ROCKNIX configuration."
systemctl restart retroid-controls-config.service >/dev/null 2>&1 || \
  fail "Could not start the persistent configuration service."
systemctl restart retroid-charge-awake.service >/dev/null 2>&1 || \
  fail "Could not start the charging sleep inhibitor."

echo "[5/6] Staging InputPlumber configuration for reboot..."
systemctl restart retroid-inputplumber-config.service >/dev/null 2>&1 || \
  fail "Could not mount the Retroid InputPlumber capability map."
systemctl restart retroid-touchpad-config.service >/dev/null 2>&1 || \
  fail "Could not mount the touchscreen configuration."
swaymsg reload >/dev/null 2>&1 || true

echo "[6/6] Verifying the installation..."
python3 - <<'PY' || fail "The EmulationStation XML files failed validation."
import xml.etree.ElementTree as ET
for path in (
    "/storage/.config/emulationstation/es_features.cfg",
    "/storage/.config/emulationstation/es_systems.cfg",
):
    ET.parse(path)
PY
grep -q '/storage/.config/input-controls/run-game.sh' \
  /storage/.config/emulationstation/es_systems.cfg || \
  fail "The common game launcher was not installed."
inputplumber devices list 2>/dev/null | grep -q 'Retroid Direct Touchscreen' || \
  fail "The touchscreen device was not detected."
systemctl is-active --quiet retroid-charge-awake.service || \
  fail "The charging sleep inhibitor is not running."

sync
echo
echo "INSTALLATION COMPLETE"
echo "Backup: ${backup_dir}"
echo "Log:    ${log_file}"
echo
echo "The device will reboot in 8 seconds to activate the native input driver."
( sleep 8; systemctl reboot ) >/dev/null 2>&1 &
sleep 6
exit 0
