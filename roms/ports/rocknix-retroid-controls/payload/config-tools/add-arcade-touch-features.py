#!/usr/bin/python3
"""Add idempotent per-game touch, mouse and trackball options to arcade cores."""

import sys
import xml.etree.ElementTree as ET

CORES = {
    "fbalpha2012",
    "fbalpha2019",
    "fbneo",
    "mame2003_plus",
    "mame2010",
    "mame2015",
    "mame2016",
    "mame",
}
FEATURE_NAMES = {"タッチ操作モード", "マウス移動量", "トラックボール慣性速度"}


def feature(name, choices):
    node = ET.Element("feature", {"name": name})
    for label, value in choices:
        ET.SubElement(node, "choice", {"name": label, "value": value})
    return node


def install(path):
    tree = ET.parse(path)
    root = tree.getroot()
    matched = 0
    for core in root.findall(".//core"):
        if core.get("name") not in CORES:
            continue
        matched += 1
        features = core.find("./features")
        if features is None:
            features = ET.SubElement(core, "features")
        for current in list(features.findall("feature")):
            if current.get("name") in FEATURE_NAMES:
                features.remove(current)
        features.append(
            feature(
                "タッチ操作モード",
                [
                    ("マウス", "mouse"),
                    ("タッチパネル", "touch"),
                    ("トラックボール（慣性あり）", "trackball"),
                ],
            )
        )
        features.append(
            feature(
                "マウス移動量",
                [(f"{value}%", str(value)) for value in range(10, 201, 10)],
            )
        )
        features.append(
            feature(
                "トラックボール慣性速度",
                [("慣性なし", "0")]
                + [(f"{value}%", str(value)) for value in (50, 75, 100, 125, 150, 200, 300)],
            )
        )
    if not matched:
        raise RuntimeError("No supported arcade core was found in es_features.cfg")
    ET.indent(tree, space="  ")
    tree.write(path, encoding="UTF-8", xml_declaration=True)


for filename in sys.argv[1:]:
    install(filename)
