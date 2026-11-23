#!/usr/bin/env bash
# Build every race x class in classes.txt: render raw frames, then shrink to game-size strips.
#   tools/char3d/build_all.sh <bodies dir> <KayKit gltf dir> <out dir> [race ...]
# Needs: python3 with `pip install bpy pillow numpy`. Bodies come from the station job `script=charbody race=<race>`.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bodies=$1 packs=$2 out=$3; shift 3
races=${*:-human elf dwarf}
mkdir -p "$out"
for r in $races; do
  while read -r kit pack acts; do
    [ -n "$kit" ] || continue
    raw="$out/raw_${r}_$kit"
    RACE=$r RES=576 ORTHO=4.59 YAW=-70 ELEV=20 SAMPLES=24 \
      python3 -I "$here/build_hero.py" -- "$bodies/$r.glb" "$packs/$pack.glb" "$raw" "$kit" "$acts" > "$out/log_${r}_$kit.txt" 2>&1
    FLIP=1 python3 "$here/post.py" "$raw" "$out/${r}_$kit" "hero_${r}_$kit" >> "$out/log_${r}_$kit.txt" 2>&1
    echo "ok $r $kit"
  done < "$here/classes.txt"
done
