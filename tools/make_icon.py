#!/usr/bin/env python3
"""Builds tools/windows/icon.ico (the Windows exe icon) from the human mage portrait already in the repository.
Crops a square round the face and scales it to 16..256 px (smooth when smaller than the crop, nearest-neighbour when
larger). A stand-in until the game has a drawn emblem that reads at 16 px. Needs Pillow. Run: python3 tools/make_icon.py"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/art/portraits/heroes/hero_human_mage.png"
OUT = ROOT / "tools/windows/icon.ico"
CROP = (20, 20, 140, 140)  # left, top, right, bottom: the face and the hand's light
SIZES = [16, 24, 32, 48, 64, 128, 256]

im = Image.open(SRC).convert("RGBA").crop(CROP)
frames = [im.resize((s, s), Image.LANCZOS if s < im.width else Image.NEAREST) for s in SIZES]
frames[-1].save(OUT, format="ICO", sizes=[(s, s) for s in SIZES], append_images=frames[:-1])
print(f"make_icon: ok {OUT.relative_to(ROOT)} sizes={SIZES}")
