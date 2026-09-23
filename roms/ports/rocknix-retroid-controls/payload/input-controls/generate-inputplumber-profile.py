#!/usr/bin/python3
"""Generate a native InputPlumber profile from Retroid per-game settings."""

import argparse
import json


BUTTONS = ("a", "b", "x", "y", "l1", "l2", "r1", "r2")
CAPABILITIES = {
    "a": ("button", "East"),
    "b": ("button", "South"),
    "x": ("button", "West"),
    "y": ("button", "North"),
    "l1": ("button", "LeftBumper"),
    "l2": ("trigger", "LeftTrigger"),
    "r1": ("button", "RightBumper"),
    "r2": ("trigger", "RightTrigger"),
}


def event(button, source=False):
    kind, name = CAPABILITIES[button]
    if kind == "button":
        return {"gamepad": {"button": name}}
    trigger = {"name": name}
    if source:
        trigger["deadzone"] = 0.3
    return {"gamepad": {"trigger": trigger}}


def yaml_value(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    with open(args.config, encoding="utf-8") as handle:
        config = json.load(handle)

    turbo_hz = max(1.0, min(60.0, float(config.get("turbo_hz", 10))))
    repeat_hz = max(1.0, min(60.0, float(config.get("repeat_hz", 10))))
    repeat_delay_ms = max(50, int(float(config.get("repeat_delay", 0.45)) * 1000))
    mappings = []
    for source in BUTTONS:
        raw = config.get("buttons", {}).get(source, "normal:" + source)
        try:
            mode, target = raw.split(":", 1)
        except ValueError:
            mode, target = "normal", source
        if mode not in ("normal", "turbo", "repeat", "toggle"):
            mode = "normal"
        if target == "all":
            targets = list(BUTTONS)
        elif target == "off":
            targets = []
        elif target in BUTTONS:
            targets = [target]
        else:
            targets = [source]
        mapping = {
            "name": f"Retroid {source.upper()}",
            "source_event": event(source, source=True),
            "target_events": [event(item) for item in targets],
            "mode": mode,
        }
        if mode == "turbo":
            mapping["frequency_hz"] = turbo_hz
        elif mode == "repeat":
            mapping["frequency_hz"] = repeat_hz
            mapping["repeat_delay_ms"] = repeat_delay_ms
        mappings.append(mapping)

    profile = {
        "version": 1,
        "kind": "DeviceProfile",
        "name": "Retroid Per-Game Controls",
        "four_way": config.get("direction_mode") == "4way",
        "left_stick_to_dpad": config.get("stick_mode") == "dpad",
        "mapping": mappings,
    }
    lines = [
        "version: 1",
        "kind: DeviceProfile",
        "name: Retroid Per-Game Controls",
        f"four_way: {'true' if profile['four_way'] else 'false'}",
        f"left_stick_to_dpad: {'true' if profile['left_stick_to_dpad'] else 'false'}",
        "mapping:",
    ]
    for mapping in mappings:
        lines += [
            f"  - name: {yaml_value(mapping['name'])}",
            f"    source_event: {yaml_value(mapping['source_event'])}",
            "    target_events:",
        ]
        if mapping["target_events"]:
            lines += [f"      - {yaml_value(target)}" for target in mapping["target_events"]]
        else:
            lines[-1] = "    target_events: []"
        lines.append(f"    mode: {mapping['mode']}")
        if "frequency_hz" in mapping:
            lines.append(f"    frequency_hz: {mapping['frequency_hz']:g}")
        if "repeat_delay_ms" in mapping:
            lines.append(f"    repeat_delay_ms: {mapping['repeat_delay_ms']}")

    temporary = args.output + ".new"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    import os
    os.replace(temporary, args.output)


if __name__ == "__main__":
    main()
