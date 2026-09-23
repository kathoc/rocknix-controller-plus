#!/usr/bin/python3
"""Install global per-game button mapping features into es_features.cfg."""

import sys
import xml.etree.ElementTree as ET

BUTTONS = [
    ("a", "A"),
    ("b", "B"),
    ("x", "X"),
    ("y", "Y"),
    ("l1", "L1"),
    ("l2", "L2"),
    ("r1", "R1"),
    ("r2", "R2"),
]
FEATURE_NAMES = {label + "ボタン設定" for _, label in BUTTONS}
FEATURE_NAMES.update({"方向入力モード", "左スティック入力", "TURBO速度", "REPEAT開始待ち", "REPEAT速度"})
OLD_ARCADE_NAMES = {"L2 ボタン割り当て", "R2 ボタン割り当て", "連射ボタン", "連射速度"}


def choice(feature, name, value):
    ET.SubElement(feature, "choice", {"name": name, "value": value})


def button_feature(source, label):
    feature = ET.Element("feature", {"name": label + "ボタン設定"})
    choice(feature, f"通常（{label}→{label}）", f"normal:{source}")
    choice(feature, "無効", "normal:off")
    for target, target_label in BUTTONS:
        if target != source:
            choice(feature, f"{target_label}へ割り当て", f"normal:{target}")
    choice(feature, "すべてのボタン", "normal:all")
    for mode, mode_label in (
        ("turbo", "TURBO"),
        ("repeat", "REPEAT"),
        ("toggle", "TOGGLE"),
    ):
        for target, target_label in BUTTONS:
            choice(feature, f"{target_label} {mode_label}", f"{mode}:{target}")
        choice(feature, f"すべての{mode_label}", f"{mode}:all")
    return feature


def speed_feature(name, entries):
    feature = ET.Element("feature", {"name": name})
    for label, value in entries:
        choice(feature, label, value)
    return feature


def install(path):
    tree = ET.parse(path)
    root = tree.getroot()

    # Remove the superseded arcade-only mapping/turbo controls and any prior
    # copy of the global controls so the operation is idempotent.
    for features in root.findall(".//features"):
        for feature in list(features.findall("feature")):
            if feature.get("name") in FEATURE_NAMES | OLD_ARCADE_NAMES:
                features.remove(feature)

    for emulator in root.findall("./emulator"):
        features = emulator.find("./features")
        if features is None:
            features = ET.Element("features")
            cores = emulator.find("./cores")
            if cores is None:
                emulator.append(features)
            else:
                emulator.insert(list(emulator).index(cores), features)
        for source, label in BUTTONS:
            features.append(button_feature(source, label))
        features.append(
            speed_feature(
                "方向入力モード",
                [("標準（8-way）", "8way"), ("4-way（斜め入力なし）", "4way")],
            )
        )
        features.append(
            speed_feature(
                "左スティック入力",
                [("ネイティブアナログ", "native"), ("十字キーとして使用", "dpad")],
            )
        )
        features.append(
            speed_feature(
                "TURBO速度",
                [("標準 10回/秒", "medium"), ("低速 6回/秒", "slow"),
                 ("高速 15回/秒", "fast"), ("最高 30回/秒", "max")],
            )
        )
        features.append(
            speed_feature(
                "REPEAT開始待ち",
                [("標準 0.45秒", "medium"), ("短い 0.25秒", "short"),
                 ("長い 0.70秒", "long")],
            )
        )
        features.append(
            speed_feature(
                "REPEAT速度",
                [("標準 10回/秒", "medium"), ("低速 6回/秒", "slow"),
                 ("高速 15回/秒", "fast"), ("最高 30回/秒", "max")],
            )
        )

    ET.indent(tree, space="  ")
    tree.write(path, encoding="UTF-8", xml_declaration=True)


for filename in sys.argv[1:]:
    install(filename)
