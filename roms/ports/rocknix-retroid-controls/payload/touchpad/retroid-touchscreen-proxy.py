#!/usr/bin/python3
"""Rotate the existing InputPlumber touchscreen without restarting InputPlumber."""

import argparse
import fcntl
import glob
import os
import select
import signal
import struct
import time

EV_SYN, EV_KEY, EV_ABS, EV_MSC = 0, 1, 3, 4
BTN_TOUCH = 330
ABS_X, ABS_Y = 0, 1
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 47, 53, 54
ABS_MT_TOOL_X, ABS_MT_TOOL_Y = 60, 61
ABS_CODES = (0, 1, 47, 48, 49, 52, 53, 54, 57, 60, 61)
BUS_USB = 3
EVENT = struct.Struct("llHHi")


def ioc(direction, kind, number, size):
    return (direction << 30) | (size << 16) | (ord(kind) << 8) | number


def iow(kind, number):
    return ioc(1, kind, number, struct.calcsize("i"))


EVIOCGRAB = iow("E", 0x90)
UI_SET_EVBIT, UI_SET_KEYBIT = iow("U", 100), iow("U", 101)
UI_SET_ABSBIT, UI_SET_MSCBIT, UI_SET_PROPBIT = iow("U", 103), iow("U", 104), iow("U", 110)
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502


def find_source():
    for _ in range(100):
        for path in glob.glob("/sys/class/input/event*/device/name"):
            try:
                if open(path, encoding="utf-8").read().strip() == "InputPlumber Touchscreen":
                    return "/dev/input/" + path.split("/")[-3]
            except OSError:
                pass
        time.sleep(0.1)
    raise RuntimeError("InputPlumber Touchscreen was not found")


class RotatedTouchscreen:
    def __init__(self, rotation):
        self.rotation = rotation % 4
        self.running = True
        self.source = os.open(find_source(), os.O_RDONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.source, EVIOCGRAB, 1)
        self.output = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        for kind in (EV_KEY, EV_ABS, EV_MSC):
            fcntl.ioctl(self.output, UI_SET_EVBIT, kind)
        fcntl.ioctl(self.output, UI_SET_KEYBIT, BTN_TOUCH)
        fcntl.ioctl(self.output, UI_SET_MSCBIT, 5)
        fcntl.ioctl(self.output, UI_SET_PROPBIT, 1)  # INPUT_PROP_DIRECT
        for code in ABS_CODES:
            fcntl.ioctl(self.output, UI_SET_ABSBIT, code)
        absmax, absmin, absfuzz, absflat = ([0] * 64 for _ in range(4))
        absmax[ABS_X] = absmax[ABS_MT_POSITION_X] = absmax[ABS_MT_TOOL_X] = 800
        absmax[ABS_Y] = absmax[ABS_MT_POSITION_Y] = absmax[ABS_MT_TOOL_Y] = 1280
        absmax[ABS_MT_SLOT] = 9
        absmax[48] = absmax[49] = 255
        absmax[52] = 1
        absmax[57] = 65535
        descriptor = struct.pack(
            "80sHHHHI" + "i" * 256,
            b"Retroid Rotated Touchscreen", BUS_USB, 0x1209, 0x8251, 1, 0,
            *(absmax + absmin + absfuzz + absflat),
        )
        os.write(self.output, descriptor)
        fcntl.ioctl(self.output, UI_DEV_CREATE)
        self.positions = {i: [0, 0] for i in range(10)}
        self.slot = 0
        time.sleep(0.15)

    def transform(self, x, y):
        nx, ny = x / 800.0, y / 1280.0
        if self.rotation == 1:
            nx, ny = ny, 1.0 - nx
        elif self.rotation == 2:
            nx, ny = 1.0 - nx, 1.0 - ny
        elif self.rotation == 3:
            nx, ny = 1.0 - ny, nx
        return round(nx * 800), round(ny * 1280)

    def emit(self, event_type, code, value):
        now = time.time()
        os.write(self.output, EVENT.pack(int(now), int(now % 1 * 1_000_000), event_type, code, value))

    def process(self, data):
        for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _, _, kind, code, value = EVENT.unpack_from(data, offset)
            if kind == EV_ABS and code == ABS_MT_SLOT:
                self.slot = max(0, min(9, value))
            if kind == EV_ABS and code in (ABS_X, ABS_MT_POSITION_X, ABS_MT_TOOL_X):
                self.positions[self.slot][0] = value
                value = self.transform(*self.positions[self.slot])[0]
            elif kind == EV_ABS and code in (ABS_Y, ABS_MT_POSITION_Y, ABS_MT_TOOL_Y):
                self.positions[self.slot][1] = value
                value = self.transform(*self.positions[self.slot])[1]
            self.emit(kind, code, value)

    def run(self):
        while self.running:
            ready, _, _ = select.select([self.source], [], [], 0.25)
            if ready:
                data = os.read(self.source, EVENT.size * 128)
                if data:
                    self.process(data)

    def stop(self, *_):
        self.running = False

    def close(self):
        fcntl.ioctl(self.source, EVIOCGRAB, 0)
        os.close(self.source)
        fcntl.ioctl(self.output, UI_DEV_DESTROY)
        os.close(self.output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rotation", type=int, default=0)
    args = parser.parse_args()
    device = RotatedTouchscreen(args.rotation)
    signal.signal(signal.SIGTERM, device.stop)
    signal.signal(signal.SIGINT, device.stop)
    try:
        device.run()
    finally:
        device.close()


if __name__ == "__main__":
    main()
