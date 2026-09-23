#!/bin/bash

set -u

inhibitor_pid=""

cleanup() {
  if [ -n "${inhibitor_pid}" ] && kill -0 "${inhibitor_pid}" 2>/dev/null; then
    kill "${inhibitor_pid}" 2>/dev/null || true
    wait "${inhibitor_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT HUP INT TERM

external_power_online() {
  local path value status

  for path in \
      /sys/class/power_supply/tcpm-source-psy-*/online \
      /sys/class/power_supply/pm8150b-charger/online; do
    [ -r "${path}" ] || continue
    read -r value < "${path}" || value=0
    case "${value}" in
      ''|*[!0-9]*) ;;
      *) [ "${value}" -gt 0 ] && return 0 ;;
    esac
  done

  if [ -r /sys/class/power_supply/battery/status ]; then
    read -r status < /sys/class/power_supply/battery/status || status=""
    case "${status}" in
      Charging|Full) return 0 ;;
    esac
  fi

  return 1
}

start_inhibitor() {
  /usr/bin/systemd-inhibit \
    --what=idle:sleep \
    --who="Retroid charge-awake" \
    --why="Keep ROCKNIX and SSH awake while external power is connected" \
    --mode=block \
    /bin/bash -c 'while true; do sleep 3600; done' &
  inhibitor_pid=$!
}

while true; do
  if external_power_online; then
    if [ -z "${inhibitor_pid}" ] || ! kill -0 "${inhibitor_pid}" 2>/dev/null; then
      wait "${inhibitor_pid}" 2>/dev/null || true
      start_inhibitor
    fi
  elif [ -n "${inhibitor_pid}" ]; then
    cleanup
    inhibitor_pid=""
  fi
  sleep 2
done
