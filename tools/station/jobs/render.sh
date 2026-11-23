#!/usr/bin/env bash
# Queue `shell` job: render game sprites with Blender on a station (tools/char3d), shrink them (post.py), make a 2x contact
# sheet and publish strips + sheet + log to the git branch art-raw under renders/<set>/<YYYYmmdd-HHMM>-<machine>/ (strips
# are over the 2 MB artifact cap, hence art-raw; at most RENDER_MAX_MB, default 45, per push; bigger files are skipped and named).
# Sets: bosses (bosses.txt, build_bosses.sh's loop), heroes (classes.txt; only= takes race names and/or class kits,
# default race human), icons (build_icons.py), town and home (build_town.py; home = HOME=1 furniture and plaques).
# Queue it: queue.sh add kind=shell args="script=render set=bosses only=boss_chandelier,boss_harvester seed=1" needs=<machine> priority=5 repeat=once timeout_s=7200
# Needs (found, or fetched once into $HH_TOOLS = ~/hh_tools): Blender + MPFB (run script=blender first), the human body glb
#   ($HH_TOOLS/bodies/<race>.glb; else taken from a charbody artifact on station-results; else made with make_body.py),
#   the KayKit Adventurers pack (CC0, cloned from github.com/KayKit-Game-Assets; its LICENSE.txt must say CC0), Pillow + numpy.
# Test hooks: RENDER_BRANCH (default art-raw), RENDER_NO_PUSH=1 (write to $RENDER_OUT, default $STATION_JOB_ART/render-out, push
#   nothing), RENDER_BODY / RENDER_KAYKIT (a body glb file, the pack's root dir), RENDER_STEP_TIMEOUT (s per Blender run, 1500).
# Summary line: PASS render set=.. made=N bytes=.. path=renders/...   or   FAIL render set=.. <reason>   (exit 1)
set -u
set=""; only=""; seed="${STATION_JOB_SEED:-1}"
for a in "$@"; do case "$a" in set=*) set="${a#set=}" ;; only=*) only="${a#only=}" ;; seed=*) seed="${a#seed=}" ;; esac; done
case "$set" in bosses | heroes | icons | town | home) ;; *) echo "FAIL render set=$set unknown set (bosses heroes icons town home)"; exit 1 ;; esac
case "$only$seed" in *[!A-Za-z0-9_,]*) echo "FAIL render set=$set bad only= or seed= (letters, digits, _ and , only)"; exit 1 ;; esac
fail() { echo "FAIL render set=$set $*"; exit 1; }
T="${HH_TOOLS:-$HOME/hh_tools}"; mkdir -p "$T" || fail "cannot make $T"
repo="$(cd "$(dirname "$0")/../../.." && pwd)"; here="$repo/tools/char3d"
art="${STATION_JOB_ART:-${TMPDIR:-/tmp}}"; mkdir -p "$art"
m="${MACHINE:-${STATION_NAME:-$(hostname)}}"; m="${m//[^A-Za-z0-9_-]/_}"
win=0; case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) win=1 ;; esac
if [ $win = 1 ]; then exe=blender.exe; p() { cygpath -w "$1"; }; else exe=blender; p() { echo "$1"; }; fi
work=$(mktemp -d); out="$work/out"; mkdir -p "$out/strips" "$out/art" "$out/sheets"; log="$out/render-log.txt"; : >"$log"
note() { echo "$*" | tee -a "$log" >&2; }
started=0
killours() { # Windows: stop only the blender.exe processes of this job (their command line names our temp dir), never the owner's own
  [ $win = 1 ] || return 0
  local mark; mark=$(basename "$work")
  powershell.exe -NoProfile -NonInteractive -Command "Get-CimInstance Win32_Process -Filter \"name='blender.exe'\" | Where-Object { \$_.CommandLine -like '*$mark*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
}
cleanup() { # never leave Blender running: kill our children; on Windows also the process tree of any blender we started
  jobs -p 2>/dev/null | xargs -r kill 2>/dev/null
  [ $started = 1 ] && killours
  rm -rf "$work"
}
trap cleanup EXIT; trap 'exit 1' INT TERM

# ---- tools: python with Pillow + numpy, Blender (or the bpy module), MPFB -------------------------------------------
B=$(find "$T/blender" -maxdepth 2 -name "$exe" -type f 2>/dev/null | head -1)
[ -n "$B" ] || { [ -s "$T/blender_path" ] && B=$(head -1 "$T/blender_path" | tr -d '\r'); }
bpymod=0; python3 -I -c "import bpy, PIL, numpy" >/dev/null 2>&1 && bpymod=1
PYX=""; PYLIB="$T/pylib"
if python3 -I -c "import PIL, numpy" >/dev/null 2>&1; then PYX=python3
elif [ -n "$B" ]; then   # Blender's own python (numpy inside); Pillow is added once under $T/pylib
  PYX=$("$B" -b --factory-startup --python-expr "import sys; print('PYEXE=' + sys.executable)" 2>/dev/null | tr -d '\r' | sed -n 's/^PYEXE=//p' | tail -1)
  [ -n "$PYX" ] || fail "cannot find Blender's python"
  if ! PYTHONPATH="$(p "$PYLIB")" "$PYX" -c "import PIL, numpy" >/dev/null 2>&1; then
    "$PYX" -m ensurepip >/dev/null 2>&1
    "$PYX" -m pip install --quiet --target "$(p "$PYLIB")" pillow numpy >>"$log" 2>&1 || fail "pip install pillow failed: $(tail -1 "$log" | cut -c1-200)"
  fi
  export PYTHONPATH="$(p "$PYLIB")"
else fail "no Blender under $T (run script=blender first) and no python with bpy"; fi
[ $bpymod = 1 ] || [ -n "$B" ] || fail "no Blender under $T (run script=blender first)"
export PYTHONDONTWRITEBYTECODE=1

run() { # run <seconds> <script> <args...>: a char3d script with bpy; killed with its process tree when over time
  local t=$1 s=$2; shift 2
  if [ $bpymod = 1 ]; then timeout -k 10 "$t" python3 -I "$s" -- "$@"
  else timeout -k 10 "$t" "$B" -b --factory-startup --python "$(p "$s")" -- "$@"; fi
  local rc=$?
  if [ $rc = 124 ] || [ $rc = 137 ]; then killours; fi
  return $rc
}
STEP="${RENDER_STEP_TIMEOUT:-1500}"
pyrun() { PYTHONDONTWRITEBYTECODE=1 timeout -k 10 600 "$PYX" "$@"; }   # Pillow-only scripts: path args need Windows form
q() { p "$1"; }

# ---- KayKit Adventurers pack (CC0) -----------------------------------------------------------------------------------
kk=""
if [ "$set" != town ] && [ "$set" != home ]; then
  kk="${RENDER_KAYKIT:-$T/kaykit/kaykit-character-pack-adventures-1.0}"
  if [ ! -d "$kk/addons" ]; then
    mkdir -p "$T/kaykit"
    GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 https://github.com/KayKit-Game-Assets/kaykit-character-pack-adventures-1.0 "$T/kaykit/kaykit-character-pack-adventures-1.0" >>"$log" 2>&1 \
      || { rm -rf "$T/kaykit/kaykit-character-pack-adventures-1.0"; fail "cannot fetch the KayKit pack: $(tail -1 "$log" | cut -c1-200)"; }
  fi
  grep -qi "CC0" "$kk/LICENSE.txt" 2>/dev/null || fail "KayKit pack licence is not CC0 (LICENSE.txt); not used"
  chars=$(ls -d "$kk"/addons/*/Characters/gltf 2>/dev/null | head -1); assets=$(ls -d "$kk"/addons/*/Assets/gltf 2>/dev/null | head -1)
  [ -d "$chars" ] || fail "KayKit pack has no Characters/gltf under $kk"
fi

# ---- the body (needs a bpy path only for bosses and heroes) ----------------------------------------------------------
getbody() { # getbody <race>: prints the glb path
  local race=$1 f="$T/bodies/$1.glb" ref n
  [ "$race" = human ] && [ -n "${RENDER_BODY:-}" ] && { echo "$RENDER_BODY"; return 0; }
  [ -s "$f" ] && { echo "$f"; return 0; }
  mkdir -p "$T/bodies"
  ( cd "$repo" && . "$repo/tools/station/queue_lib.sh" >/dev/null 2>&1 && gb_fetch station-results
    ref=$(git ls-tree -r --name-only refs/remotes/origin/station-results 2>/dev/null | grep "/art/.*-$race\.glb\$" | tail -1)
    [ -n "$ref" ] && git show "refs/remotes/origin/station-results:$ref" >"$f.part" 2>/dev/null && [ "$(wc -c <"$f.part")" -gt 100000 ] && mv "$f.part" "$f"
    rm -f "$f.part" ) 2>/dev/null
  [ -s "$f" ] && { echo "$f"; return 0; }
  [ -d "$T/mpfb2/src/mpfb" ] || return 1
  n="$work/body_$race"; mkdir -p "$n"
  run 900 "$here/make_body.py" "$(p "$T/mpfb2/src")" "$(p "$n")" "$race" >>"$log" 2>&1
  [ -s "$n/$race.glb" ] && { cp "$n/$race.glb" "$f"; echo "$f"; return 0; }
  return 1
}

# ---- build -----------------------------------------------------------------------------------------------------------
IFS=, read -r -a want <<<"$only"
wanted() { [ ${#want[@]} -eq 0 ] && return 0; local w; for w in "${want[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }
built=0; started=1
case "$set" in
  bosses)
    body=$(getbody human) || fail "no human body glb (queue script=charbody, or script=blender first)"
    while read -r name pack acts envs; do
      [ -n "$name" ] && wanted "$name" || continue
      raw="$work/raw_$name"; k=$(p "$chars")
      case "$pack" in
        skel:*) note "skip $name: needs the KayKit Skeletons pack"; continue ;;
        -) ( export YAW=-70 ELEV=20 SAMPLES=16 $envs; run "$STEP" "$here/build_beast.py" "$(p "$raw")" "${name#boss_}" "$acts" ) >"$out/log_$name.txt" 2>&1 ;;
        *) ( export RACE=human YAW=-70 ELEV=20 SAMPLES=16 $envs; run "$STEP" "$here/build_hero.py" "$(p "$body")" "$(p "$chars/$pack.glb")" "$(p "$raw")" "$name" "$acts" ) >"$out/log_$name.txt" 2>&1 ;;
      esac
      rc=$?
      [ $rc = 0 ] && FLIP=1 pyrun "$here/post.py" "$(p "$raw")" "$(p "$out/strips")" "$name" >>"$out/log_$name.txt" 2>&1; rc=$?
      if [ $rc = 0 ]; then built=$((built + 1)); note "ok $name"; else note "FAILED $name rc=$rc: $(tail -2 "$out/log_$name.txt" | tr -d '\r' | tr '\n' ' ' | cut -c1-300)"; fi
    done <"$here/bosses.txt"
    # contact sheets: import into a scratch art dir, then review_bosses.py (2x, edge checks)
    if [ $built -gt 0 ]; then
      pyrun "$here/import_sprites.py" monsters "$(p "$out/strips")" "$(p "$out/art")" >>"$log" 2>&1
      slugs=$(cd "$out/art" && ls boss_*_walk.json 2>/dev/null | sed 's/^boss_//; s/_walk\.json$//')
      pyrun "$here/review_bosses.py" "$(p "$out/art")" "$(p "$out/sheets")" $slugs >>"$log" 2>&1 || note "review_bosses failed"
      [ -s "$out/sheets/bosses_walk_2x.png" ] && mv "$out/sheets/bosses_walk_2x.png" "$out/sheet_2x.png"
    fi ;;
  heroes)
    races=""; kits=""
    for w in "${want[@]}"; do case "$w" in human | elf | dwarf | orc) races="$races $w" ;; *) kits="$kits $w" ;; esac; done
    for r in ${races:-human}; do
      body=$(getbody "$r") || { note "no $r body glb"; continue; }
      while read -r kit pack acts; do
        [ -n "$kit" ] || continue
        [ -z "$kits" ] || [[ " $kits " == *" $kit "* ]] || continue
        raw="$work/raw_${r}_$kit"
        ( export RACE=$r RES=576 ORTHO=4.59 YAW=-70 ELEV=20 SAMPLES=24; run "$STEP" "$here/build_hero.py" "$(p "$body")" "$(p "$chars/$pack.glb")" "$(p "$raw")" "$kit" "$acts" ) >"$out/log_${r}_$kit.txt" 2>&1
        rc=$?
        [ $rc = 0 ] && FLIP=1 pyrun "$here/post.py" "$(p "$raw")" "$(p "$out/strips")" "hero_${r}_$kit" >>"$out/log_${r}_$kit.txt" 2>&1; rc=$?
        if [ $rc = 0 ]; then built=$((built + 1)); note "ok $r $kit"; else note "FAILED $r $kit rc=$rc: $(tail -2 "$out/log_${r}_$kit.txt" | tr -d '\r' | tr '\n' ' ' | cut -c1-300)"; fi
      done <"$here/classes.txt"
    done
    ls "$out"/strips/*_walk.png >/dev/null 2>&1 && pyrun "$here/strips_sheet.py" "$(p "$out/sheet_2x.png")" $(ls "$out"/strips/*_walk.png | while read -r f; do p "$f"; done) >>"$log" 2>&1 ;;
  icons)
    [ -d "$assets" ] || fail "KayKit pack has no Assets/gltf"
    pyrun "$here/build_icons.py" "$(p "$out/strips")" "$(p "$assets")" $(echo "${only//,/ }" | sed 's/\bui_//g') >>"$log" 2>&1 || fail "build_icons failed: $(tail -2 "$log" | cut -c1-300)"
    built=$(ls "$out"/strips/*.png 2>/dev/null | wc -l)
    pyrun "$here/icons_sheet.py" "$(p "$out/strips")" "$(p "$out/sheets")" >>"$log" 2>&1 && [ -s "$out/sheets/icons_sheet.png" ] && mv "$out/sheets/icons_sheet.png" "$out/sheet_2x.png" ;;
  town | home)
    ids=$(echo "${only//,/ }")
    if [ $set = home ]; then ( export HOME=1; run "$STEP" "$here/build_town.py" "$(p "$work/town")" "$(p "$out/strips")" $ids ) >"$log.town" 2>&1
    else run "$STEP" "$here/build_town.py" "$(p "$work/town")" "$(p "$out/strips")" $ids >"$log.town" 2>&1; fi
    rc=$?; cat "$log.town" >>"$log"; rm -f "$log.town"
    built=$(ls "$out"/strips/ui_*.png 2>/dev/null | wc -l)
    [ $rc = 0 ] || note "build_town ended $rc"
    [ $built -gt 0 ] && pyrun "$here/strips_sheet.py" "$(p "$out/sheet_2x.png")" $(ls "$out"/strips/ui_*.png | while read -r f; do p "$f"; done) >>"$log" 2>&1 ;;
esac
[ $built -gt 0 ] || fail "nothing was built: $(tail -3 "$log" | tr -d '\r' | tr '\n' ' ' | cut -c1-400)"

# ---- publish ---------------------------------------------------------------------------------------------------------
stamp=$(date -u +%Y%m%d-%H%M); rel="renders/$set/$stamp-$m"
ops=(); put=0; bytes=0; skipped=""; cap=$(( ${RENDER_MAX_MB:-45} * 1048576 ))
files=$(cd "$out" && find strips sheets art sheet_2x.png render-log.txt log_*.txt -type f 2>/dev/null | grep -v '^art/' | while read -r f; do echo "$(wc -c <"$out/$f" | tr -d ' ') $f"; done | sort -n)
dest="${RENDER_OUT:-$art/render-out}/$rel"
[ "${RENDER_NO_PUSH:-0}" = 1 ] && mkdir -p "$dest"
while read -r sz f; do
  [ -n "$f" ] || continue
  if [ $((bytes + sz)) -gt "$cap" ]; then skipped="$skipped $f"; continue; fi
  bytes=$((bytes + sz)); put=$((put + 1))
  if [ "${RENDER_NO_PUSH:-0}" = 1 ]; then mkdir -p "$dest/$(dirname "$f")"; cp "$out/$f" "$dest/$f"; else ops+=("+$rel/$f:$out/$f"); fi
done <<<"$files"
[ -z "$skipped" ] || echo "render: over $((cap / 1048576)) MB, not published:$skipped" >&2
if [ "${RENDER_NO_PUSH:-0}" != 1 ]; then
  ( cd "$repo" && MACHINE="$m" BRANCH=station-results && . "$repo/tools/station/queue_lib.sh" \
    && GIT_TERMINAL_PROMPT=0 gb_put_retry "${RENDER_BRANCH:-art-raw}" "$m: render $set $stamp" "${ops[@]}" ) || fail "push to ${RENDER_BRANCH:-art-raw} failed (built $built, $bytes bytes)"
fi
echo "PASS render set=$set made=$built bytes=$bytes path=$rel${skipped:+ skipped=$(echo $skipped | wc -w)}"
