#!/usr/bin/python3
"""Route every normal game launch through the shared input-control wrapper."""

import sys
import re

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    text = re.sub(
        r"(<command>)/(?:usr/bin/runemu\.sh|storage/\.config/arcade-controls/run-arcade\.sh)(?=\s)",
        r"\1/storage/.config/input-controls/run-game.sh",
        text,
    )
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
