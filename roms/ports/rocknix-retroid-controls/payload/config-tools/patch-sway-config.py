#!/usr/bin/python3
"""Install the Sway input blocks used by the Retroid touch modes."""

import re
import sys

BEGIN = "# BEGIN RETROID CONTROLS"
END = "# END RETROID CONTROLS"
BLOCK = """# BEGIN RETROID CONTROLS
# InputPlumber emits F12 only for the native HOME + Back chord.
bindsym --no-repeat F12 exec /storage/.config/input-controls/retroid-osd-trigger.py

# Treat the Retroid touchscreen as a relative trackpad.
input "0:65535:InputPlumber_Touchpad" {
    tap enabled
    tap_button_map lrm
    scroll_method two_finger
}

# Direct-touch mode used by per-game arcade settings.
input "10248:4117:InputPlumber_Touchscreen" {
    map_to_output DSI-1
}

# Rotated per-game direct-touch proxy.
input "4617:33361:Retroid_Rotated_Touchscreen" {
    map_to_output DSI-1
}

# Keep the userspace trackball's movement percentages predictable.
input "4617:33360:Retroid_Trackball" {
    accel_profile flat
}
# END RETROID CONTROLS
"""


def install(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    # Remove a prior managed block and the exact legacy unmarked input blocks
    # from earlier builds. Other user Sway settings remain untouched.
    text = re.sub(
        rf"\n?{re.escape(BEGIN)}.*?{re.escape(END)}\n?",
        "\n",
        text,
        flags=re.DOTALL,
    )
    identifiers = (
        "0:65535:InputPlumber_Touchpad",
        "10248:4117:InputPlumber_Touchscreen",
        "0:65535:InputPlumber_Touchscreen",
        "4617:33360:Retroid_Trackball",
        "4617:33361:Retroid_Rotated_Touchscreen",
    )
    for identifier in identifiers:
        text = re.sub(
            rf'\n?input\s+"{re.escape(identifier)}"\s*\{{.*?\}}\s*',
            "\n",
            text,
            flags=re.DOTALL,
        )
    text = re.sub(
        r"\n?# (?:Treat the Retroid touchscreen|Direct-touch mode|Keep the userspace trackball).*?\n",
        "\n",
        text,
    )
    text = text.rstrip() + "\n\n" + BLOCK
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


for filename in sys.argv[1:]:
    install(filename)
