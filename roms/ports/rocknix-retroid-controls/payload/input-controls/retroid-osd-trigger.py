#!/usr/bin/python3
"""Open the per-game OSD after HOME and Back are physically released."""
import fcntl
import glob
import os
import signal
import struct
import time

BTN_MODE = 316
BTN_BACK = 278


def ioc(direction, kind, number, size):
    return (direction << 30) | (size << 16) | (ord(kind) << 8) | number


def chord_is_pressed():
    """Read HOME and Back from the physical MCU device when available."""
    request = ioc(2, "E", 0x18, 96)  # EVIOCGKEY(96)
    virtual_guide = False
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        try:
            with open(name_path, encoding="utf-8") as handle:
                name = handle.read().strip()
            if name not in (
                "Retroid Pocket Gamepad",
                "Sony Interactive Entertainment DualSense Wireless Controller",
            ):
                continue
            event = name_path.split("/")[-3]
            with open("/dev/input/" + event, "rb", buffering=0) as handle:
                keys = bytearray(96)
                fcntl.ioctl(handle.fileno(), request, keys, True)
            home = bool(keys[BTN_MODE // 8] & (1 << (BTN_MODE % 8)))
            if name == "Retroid Pocket Gamepad":
                back = bool(keys[BTN_BACK // 8] & (1 << (BTN_BACK % 8)))
                return home or back
            virtual_guide = virtual_guide or home
        except OSError:
            continue
    return virtual_guide


# The Sway binding fires on F12 key-down while the chord is still held. If the
# OSD grabs the virtual devices at that instant, RetroArch can miss either
# release and retain a stuck hotkey state. Wait for both real releases first.
deadline = time.monotonic() + 10.0
while chord_is_pressed() and time.monotonic() < deadline:
    time.sleep(0.02)

if chord_is_pressed():
    raise SystemExit(0)

# Let InputPlumber forward both release events before the OSD grabs its targets.
time.sleep(0.05)

try:
    with open("/tmp/retroid-game-osd.pid", encoding="ascii") as handle:
        os.kill(int(handle.read()), signal.SIGUSR1)
except (OSError, ValueError):
    pass
