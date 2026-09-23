#!/usr/bin/python3
"""Turn the InputPlumber virtual touchpad into an inertial relative mouse."""

import argparse
import fcntl
import glob
import math
import os
import select
import signal
import struct
import sys
import time

EV_SYN = 0
EV_KEY = 1
EV_REL = 2
EV_ABS = 3
SYN_REPORT = 0
REL_X = 0
REL_Y = 1
BTN_LEFT = 272
BTN_RIGHT = 273
BTN_TOUCH = 330
ABS_MT_SLOT = 47
ABS_MT_TRACKING_ID = 57
ABS_MT_POSITION_X = 53
ABS_MT_POSITION_Y = 54

BUS_USB = 3
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502


def ioc(direction, kind, number, size):
    return (direction << 30) | (size << 16) | (ord(kind) << 8) | number


def iow(kind, number):
    return ioc(1, kind, number, struct.calcsize("i"))


EVIOCGRAB = iow("E", 0x90)
UI_SET_EVBIT = iow("U", 100)
UI_SET_KEYBIT = iow("U", 101)
UI_SET_RELBIT = iow("U", 102)
EVENT = struct.Struct("llHHi")


def find_touchpad(timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for name_path in glob.glob("/sys/class/input/event*/device/name"):
            try:
                with open(name_path, encoding="utf-8") as handle:
                    if handle.read().strip() in ("InputPlumber Touchpad", "InputPlumber Touchscreen"):
                        event_name = name_path.split("/")[-3]
                        return "/dev/input/" + event_name
            except OSError:
                pass
        time.sleep(0.1)
    raise RuntimeError("InputPlumber touch device was not found")


class VirtualMouse:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_REL)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, BTN_LEFT)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, BTN_RIGHT)
        fcntl.ioctl(self.fd, UI_SET_RELBIT, REL_X)
        fcntl.ioctl(self.fd, UI_SET_RELBIT, REL_Y)
        values = [0] * (64 * 4)
        descriptor = struct.pack(
            "80sHHHHI" + "i" * len(values),
            b"Retroid Trackball",
            BUS_USB,
            0x1209,
            0x8250,
            1,
            0,
            *values,
        )
        os.write(self.fd, descriptor)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        time.sleep(0.15)

    def event(self, event_type, code, value):
        now = time.time()
        sec = int(now)
        usec = int((now - sec) * 1_000_000)
        os.write(self.fd, EVENT.pack(sec, usec, event_type, code, int(value)))

    def sync(self):
        self.event(EV_SYN, SYN_REPORT, 0)

    def move(self, dx, dy):
        if dx:
            self.event(EV_REL, REL_X, dx)
        if dy:
            self.event(EV_REL, REL_Y, dy)
        if dx or dy:
            self.sync()

    def click(self, button):
        self.event(EV_KEY, button, 1)
        self.sync()
        self.event(EV_KEY, button, 0)
        self.sync()

    def close(self):
        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        finally:
            os.close(self.fd)


class Trackball:
    def __init__(self, gain, inertia, rotation):
        self.gain = 1.50 * gain
        self.inertia = inertia
        self.rotation = rotation % 4
        self.mouse = VirtualMouse()
        self.source_fd = os.open(find_touchpad(), os.O_RDONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.source_fd, EVIOCGRAB, 1)
        self.running = True
        self.slot = 0
        self.slots = {i: {"active": False, "x": None, "y": None} for i in range(10)}
        self.was_touching = False
        self.last_x = None
        self.last_y = None
        self.last_motion_time = None
        self.touch_started = 0.0
        self.travel = 0.0
        self.max_contacts = 0
        self.vx = 0.0
        self.vy = 0.0
        self.frac_x = 0.0
        self.frac_y = 0.0
        self.last_tick = time.monotonic()

    def active_contacts(self):
        return sum(1 for slot in self.slots.values() if slot["active"])

    def emit_float_move(self, dx, dy):
        self.frac_x += dx
        self.frac_y += dy
        out_x = math.trunc(self.frac_x)
        out_y = math.trunc(self.frac_y)
        self.frac_x -= out_x
        self.frac_y -= out_y
        self.mouse.move(out_x, out_y)

    def report(self):
        now = time.monotonic()
        primary = self.slots[0]
        touching = primary["active"] and primary["x"] is not None and primary["y"] is not None
        contacts = self.active_contacts()
        self.max_contacts = max(self.max_contacts, contacts)

        if touching and not self.was_touching:
            self.vx = self.vy = 0.0
            self.last_x = primary["x"]
            self.last_y = primary["y"]
            self.last_motion_time = now
            self.touch_started = now
            self.travel = 0.0
            self.max_contacts = max(1, contacts)
        elif touching and self.was_touching:
            dx_raw = primary["x"] - self.last_x
            dy_raw = primary["y"] - self.last_y
            if self.rotation == 1:
                dx_raw, dy_raw = dy_raw, -dx_raw
            elif self.rotation == 2:
                dx_raw, dy_raw = -dx_raw, -dy_raw
            elif self.rotation == 3:
                dx_raw, dy_raw = -dy_raw, dx_raw
            if dx_raw or dy_raw:
                dt = max(0.001, now - self.last_motion_time)
                dx = dx_raw * self.gain
                dy = dy_raw * self.gain
                self.emit_float_move(dx, dy)
                instant_vx = dx / dt
                instant_vy = dy / dt
                self.vx = self.vx * 0.45 + instant_vx * 0.55
                self.vy = self.vy * 0.45 + instant_vy * 0.55
                self.travel += math.hypot(dx_raw, dy_raw)
                self.last_x = primary["x"]
                self.last_y = primary["y"]
                self.last_motion_time = now
        elif not touching and self.was_touching:
            duration = now - self.touch_started
            if duration <= 0.28 and self.travel <= 18:
                self.vx = self.vy = 0.0
                self.mouse.click(BTN_RIGHT if self.max_contacts >= 2 else BTN_LEFT)
            else:
                self.vx *= self.inertia
                self.vy *= self.inertia
                speed = math.hypot(self.vx, self.vy)
                if speed > 5000:
                    ratio = 5000 / speed
                    self.vx *= ratio
                    self.vy *= ratio
            self.last_x = self.last_y = None
            self.last_motion_time = None
            self.max_contacts = 0
        self.was_touching = touching

    def coast(self):
        now = time.monotonic()
        dt = min(0.05, now - self.last_tick)
        self.last_tick = now
        if self.was_touching:
            return
        speed = math.hypot(self.vx, self.vy)
        if speed < 5:
            self.vx = self.vy = 0.0
            return
        self.emit_float_move(self.vx * dt, self.vy * dt)
        decay = math.exp(-4.2 * dt)
        self.vx *= decay
        self.vy *= decay

    def process(self, data):
        for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _, _, event_type, code, value = EVENT.unpack_from(data, offset)
            if event_type == EV_ABS:
                if code == ABS_MT_SLOT:
                    self.slot = max(0, min(9, value))
                elif code == ABS_MT_TRACKING_ID:
                    self.slots[self.slot]["active"] = value >= 0
                    if value < 0:
                        self.slots[self.slot]["x"] = None
                        self.slots[self.slot]["y"] = None
                elif code == ABS_MT_POSITION_X:
                    self.slots[self.slot]["x"] = value
                elif code == ABS_MT_POSITION_Y:
                    self.slots[self.slot]["y"] = value
            elif event_type == EV_KEY and code == BTN_TOUCH and value == 0:
                self.slots[0]["active"] = False
            elif event_type == EV_SYN and code == SYN_REPORT:
                self.report()

    def run(self):
        while self.running:
            ready, _, _ = select.select([self.source_fd], [], [], 1 / 120)
            if ready:
                try:
                    data = os.read(self.source_fd, EVENT.size * 128)
                except BlockingIOError:
                    data = b""
                if data:
                    self.process(data)
            self.coast()

    def stop(self, *_):
        self.running = False

    def close(self):
        try:
            fcntl.ioctl(self.source_fd, EVIOCGRAB, 0)
        except OSError:
            pass
        os.close(self.source_fd)
        self.mouse.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--movement", type=float, default=100.0)
    parser.add_argument("--inertia", type=float, default=100.0)
    parser.add_argument("--rotation", type=int, default=0)
    args = parser.parse_args()
    trackball = Trackball(
        max(0.1, args.movement / 100),
        max(0.0, args.inertia / 100),
        args.rotation,
    )
    signal.signal(signal.SIGTERM, trackball.stop)
    signal.signal(signal.SIGINT, trackball.stop)
    try:
        trackball.run()
    finally:
        trackball.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"retroid-trackball: {error}", file=sys.stderr)
        raise
