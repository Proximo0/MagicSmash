#!/usr/bin/env python3
"""Copies loop points from tools/music/out/<name>.loop.json into the Godot
import settings of assets/audio/<name>.wav (QOA compression, forward loop).
Run after rendering music, then let Godot re-import (open the editor, or
`godot --headless --editor --quit`)."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "audio"))
OUT = os.path.join(HERE, "out")

PARAMS = """[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode={mode}
edit/loop_begin={begin}
edit/loop_end={end}
compress/mode=2
"""

for name in ("music_title", "music_battle", "music_library", "music_sanctum", "music_boss", "music_gameover"):
    meta_path = os.path.join(OUT, name + ".loop.json")
    imp = os.path.join(AUDIO, name + ".wav.import")
    if not os.path.exists(meta_path):
        print("skip (no render):", name)
        continue
    meta = json.load(open(meta_path))
    params = PARAMS.format(mode=2 if meta["loop"] else 1, begin=meta["loop_begin"],
                           end=meta["loop_end"] if meta["loop"] else -1)
    if os.path.exists(imp):
        txt = open(imp).read()
        txt = re.sub(r"\[params\].*", params, txt, flags=re.S)
    else:
        txt = '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n' + params
    open(imp, "w").write(txt)
    print(f"{name}: loop={meta['loop']} begin={meta['loop_begin']} end={meta['loop_end']}")
