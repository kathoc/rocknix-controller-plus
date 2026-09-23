#!/usr/bin/python3
"""Remove only configuration entries managed by Retroid Controls."""

import argparse
import re
import xml.etree.ElementTree as ET

FEATURE_NAMES = {
    "Aボタン設定",
    "Bボタン設定",
    "Xボタン設定",
    "Yボタン設定",
    "L1ボタン設定",
    "L2ボタン設定",
    "R1ボタン設定",
    "R2ボタン設定",
    "方向入力モード",
    "左スティック入力",
    "TURBO速度",
    "REPEAT開始待ち",
    "REPEAT速度",
    "タッチ操作モード",
    "マウス移動量",
    "トラックボール慣性速度",
    # Names used by the earlier arcade-only version.
    "L2 ボタン割り当て",
    "R2 ボタン割り当て",
    "連射ボタン",
    "連射速度",
}


def remove_features(path):
    tree = ET.parse(path)
    root = tree.getroot()
    for parent in root.iter():
        for features in list(parent.findall("features")):
            for feature in list(features.findall("feature")):
                if feature.get("name") in FEATURE_NAMES:
                    features.remove(feature)
            if not list(features) and not features.attrib and not (features.text or "").strip():
                parent.remove(features)
    ET.indent(tree, space="  ")
    tree.write(path, encoding="UTF-8", xml_declaration=True)


def remove_launcher(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    text = text.replace(
        "<command>/storage/.config/input-controls/run-game.sh ",
        "<command>/usr/bin/runemu.sh ",
    )
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def remove_sway(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    text = re.sub(
        r"\n?# BEGIN RETROID CONTROLS.*?# END RETROID CONTROLS\n?",
        "\n",
        text,
        flags=re.DOTALL,
    )
    text = re.sub(r"\n{3,}", "\n\n", text).rstrip() + "\n"
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def remove_settings(path):
    escaped = "|".join(re.escape(name) for name in sorted(FEATURE_NAMES, key=len, reverse=True))
    feature_setting = re.compile(rf"^[^=]+\.(?:{escaped})=")
    with open(path, encoding="utf-8") as handle:
        lines = handle.readlines()
    with open(path, "w", encoding="utf-8") as handle:
        for line in lines:
            if feature_setting.match(line):
                continue
            if line.rstrip("\n") == "global.analogue=0":
                continue
            handle.write(line)


parser = argparse.ArgumentParser()
parser.add_argument("--features", required=True)
parser.add_argument("--systems", required=True)
parser.add_argument("--sway", required=True)
parser.add_argument("--settings", required=True)
args = parser.parse_args()

remove_features(args.features)
remove_launcher(args.systems)
remove_sway(args.sway)
remove_settings(args.settings)
