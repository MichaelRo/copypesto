#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Writes the iOS alternate app icons, one Icon Composer file per theme, from Sources/Resources/Pesto.icon.

The rule is ADR 0013's: the ground carries the theme, the cards stay garlic glass, and the P is the theme's accent.
Light uses the theme's ground (the colors brand-art.py draws the Mac's theme icons with); dark keeps Basil's dark
ground. The P sits on the garlic front card in both, so it is the theme's deep accent in both, as Basil's is: a light
accent on garlic did not read (checked with ictool). Run: python3 design/source/theme-icons.py
"""
import json
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Sources/Resources/Pesto.icon"

# Light ground top and bottom, the P in light, the P in dark (brand-art.py ICONS, variant A).
THEMES = {
    "PestoParmesan": ("#3A3F37", "#1F2320", "#7A5F00", "#7A5F00"),
    "PestoPineNut": ("#EBD9B4", "#D2BA86", "#8A4F16", "#8A4F16"),
    "PestoMortar": ("#F4F1E8", "#D8D3C4", "#3F5446", "#3F5446"),
}


def srgb(hex_color):
    value = hex_color.lstrip("#")
    channels = [int(value[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return "extended-srgb:" + ",".join(f"{c:.5f}" for c in channels) + ",1.00000"


for name, (top, bottom, letter, letter_dark) in THEMES.items():
    target = ROOT / f"Sources/Resources/{name}.icon"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(SOURCE, target)
    manifest_path = target / "icon.json"
    manifest = json.loads(manifest_path.read_text())
    for fill in manifest["fill-specializations"]:
        if "appearance" not in fill:
            fill["value"]["linear-gradient"] = [srgb(top), srgb(bottom)]
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    for file_name, color in (("letter.svg", letter), ("letter-dark.svg", letter_dark)):
        path = target / "Assets" / file_name
        path.write_text(re.sub(r'fill="#[0-9A-Fa-f]{6}"', f'fill="{color}"', path.read_text()))
    print("wrote", target.relative_to(ROOT))
