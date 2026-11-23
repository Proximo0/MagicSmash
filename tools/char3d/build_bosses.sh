#!/usr/bin/env bash
# Render the field bosses of bosses.txt (name, KayKit pack or - for a beast, actions, env) at 2.2x the monsters' pixels.
#   tools/char3d/build_bosses.sh <human body glb> <KayKit gltf dir> <out dir> [name ...]
# then: python3 tools/char3d/import_sprites.py monsters <out dir>/strips realm/client/art
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
body=$1 packs=$2 out=$3; shift 3
only=" ${*} "
mkdir -p "$out/strips"
while read -r name pack acts envs; do
  [ -n "$name" ] || continue
  [ $# -eq 0 ] || [[ "$only" == *" $name "* ]] || continue
  raw="$out/raw_$name"
  if [ "$pack" = "-" ]; then
    env YAW=-70 ELEV=20 SAMPLES=16 $envs python3 -I "$here/build_beast.py" -- "$raw" "${name#boss_}" "$acts" > "$out/log_$name.txt" 2>&1
  else
    env RACE=human YAW=-70 ELEV=20 SAMPLES=16 $envs python3 -I "$here/build_hero.py" -- "$body" "$packs/$pack.glb" "$raw" "$name" "$acts" > "$out/log_$name.txt" 2>&1
  fi
  FLIP=1 python3 -I "$here/post.py" "$raw" "$out/strips" "$name" >> "$out/log_$name.txt" 2>&1
  echo "ok $name"
done < "$here/bosses.txt"
