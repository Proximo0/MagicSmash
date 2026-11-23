#!/usr/bin/env bash
# Queue `shell` job: put Blender (GPL, free) and the MPFB human generator (GPL code, CC0 body data) on this station for
# the 3D character route (Curtis, 22 Nov 2026 23:32 UTC, decision card: "Yes, all four PCs"). No installer and no
# admin: the official portable archive from download.blender.org is unpacked under ~/hh_tools/blender, MPFB is cloned
# under ~/hh_tools/mpfb2. Then a self test: Blender starts without a window, makes one rigged human and renders one
# small frame on the processor. Safe to run again: it skips what is already there.
# Queue it: queue.sh add kind=shell args=script=blender needs=<machine> priority=9 repeat=once timeout_s=3600
# Summary line: PASS|FAIL blender version=... mpfb=... human_verts=... render_s=... gpu=...
set -u
T="${HH_TOOLS:-$HOME/hh_tools}"; mkdir -p "$T" || { echo "FAIL blender cannot make $T"; exit 1; }
art="${STATION_JOB_ART:-${TMPDIR:-/tmp}}"; mkdir -p "$art" 2>/dev/null
m="${MACHINE:-${STATION_NAME:-$(hostname)}}"
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) os=windows; pat='windows-x64\.zip'; exe="blender.exe" ;;
  *) os=linux; pat='linux-x64\.tar\.xz'; exe="blender" ;;
esac
find_exe() { find "$T/blender" -maxdepth 2 -name "$exe" -type f 2>/dev/null | head -1; }
B="$(find_exe)"
if [ -n "$B" ] && ! "$B" --version >/dev/null 2>&1; then   # a half-unpacked copy: the program is there but cannot start
  echo "blender: $B does not start, unpacking again" >&2; rm -rf "$T/blender"; B=""
fi
if [ -z "$B" ]; then
  base="https://download.blender.org/release"
  ser=$(curl -fsSL "$base/" | grep -oE 'Blender[0-9]+\.[0-9]+/' | sort -V | uniq | tail -4 | tac)
  url=""
  for s in $ser; do                                   # newest series that already has a build for this system
    f=$(curl -fsSL "$base/$s" | grep -oE "blender-[0-9.]+-$pat" | sort -V | uniq | tail -1)
    [ -n "$f" ] && { url="$base/$s$f"; break; }
  done
  [ -n "$url" ] || { echo "FAIL blender no download found at $base (series: $(echo $ser | tr '\n' ' '))"; exit 1; }
  mkdir -p "$T/blender" && cd "$T/blender" || exit 1
  a="$(basename "$url")"
  curl -fSL --retry 3 -o "$a" "$url" 2>"$art/$m-blender-dl.txt" || { echo "FAIL blender download $url: $(tail -1 "$art/$m-blender-dl.txt" | cut -c1-120)"; exit 1; }
  sum=$(curl -fsSL "${url%/*}/$(echo "$a" | sed -E 's/^(blender-[0-9.]+)-.*/\1/').sha256" 2>/dev/null | grep -F "$a" | cut -d' ' -f1)
  have=$(sha256sum "$a" | cut -d' ' -f1)
  [ -z "$sum" ] || [ "$sum" = "$have" ] || { rm -f "$a"; echo "FAIL blender checksum of $a does not match the published one"; exit 1; }
  if [ "$os" = windows ]; then   # Windows' own tar reads zip and is far faster than Expand-Archive, which stopped part way on the laptop
    wtar="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32/tar.exe"
    if [ -x "$wtar" ]; then "$wtar" -xf "$a" 2>"$art/$m-blender-unpack.txt"; else unzip -q -o "$a" 2>"$art/$m-blender-unpack.txt"; fi
    urc=$?
  else
    tar -xf "$a" 2>"$art/$m-blender-unpack.txt"; urc=$?
  fi
  [ "$urc" = 0 ] || { rm -rf "$T/blender"; echo "FAIL blender unpack of $a ended $urc: $(tail -2 "$art/$m-blender-unpack.txt" | tr '\n' ' ' | cut -c1-200)"; exit 1; }
  rm -f "$a"
  B="$(find_exe)"
  [ -n "$B" ] || { echo "FAIL blender unpacked but $exe not found under $T/blender"; exit 1; }
  checked=$([ -n "$sum" ] && echo yes || echo no-list)
else
  checked=kept
fi
if [ ! -d "$T/mpfb2/src/mpfb" ]; then
  git clone -q --depth 1 https://github.com/makehumancommunity/mpfb2 "$T/mpfb2" 2>"$art/$m-mpfb.txt" || { echo "FAIL blender mpfb clone: $(tail -1 "$art/$m-mpfb.txt" | cut -c1-120)"; exit 1; }
fi
mp=$(git -C "$T/mpfb2" rev-parse --short HEAD 2>/dev/null)
test_py="$T/blender_selftest.py"
cat > "$test_py" <<'EOF'
import sys, time, bpy
src, out = sys.argv[sys.argv.index("--") + 1:][:2]
import os, shutil, importlib, addon_utils
bpy.ops.wm.read_factory_settings(use_empty=True)
# Blender 5 only lets the generator find its own folders when it is loaded as an extension, not from sys.path
dest = os.path.join(bpy.utils.user_resource("EXTENSIONS", path="user_default", create=True), "mpfb")
if not os.path.isdir(dest):
    shutil.copytree(os.path.join(src, "mpfb"), dest)
M = "bl_ext.user_default.mpfb"
addon_utils.enable(M, default_set=False)
HumanService = importlib.import_module(M + ".services.humanservice").HumanService
h = HumanService.create_human()
rig = HumanService.add_builtin_rig(h, "game_engine")
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.samples = 8; sc.cycles.device = "CPU"
sc.render.resolution_x = sc.render.resolution_y = 256; sc.render.film_transparent = True
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = 2.4; cam.location = (0, -8, 0.9); cam.rotation_euler = (1.5708, 0, 0); sc.camera = cam
sun = bpy.data.objects.new("s", bpy.data.lights.new("s", "SUN")); sun.data.energy = 4; sun.rotation_euler = (0.9, 0, 0.5); sc.collection.objects.link(sun)
t = time.time(); sc.render.filepath = out; bpy.ops.render.render(write_still=True)
print("SELFTEST version=%s human_verts=%d bones=%d render_s=%.1f" % (bpy.app.version_string, len(h.data.vertices), len(rig.data.bones), time.time() - t))
EOF
p() { if [ "$os" = windows ]; then cygpath -w "$1"; else echo "$1"; fi; }
log="$art/$m-blender.txt"
"$B" -b --factory-startup --python "$(p "$test_py")" -- "$(p "$T/mpfb2/src")" "$(p "$art/$m-blender-human.png")" >"$log" 2>&1
rc=$?
line=$(grep -a "^SELFTEST" "$log" | tail -1 | tr -d '\r')
gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | tr -d '\r'); [ -n "$gpu" ] || gpu=none
if [ -n "$line" ] && [ -s "$art/$m-blender-human.png" ]; then
  echo "PASS blender ${line#SELFTEST } mpfb=$mp archive_checksum=$checked gpu=[$gpu] at=$T"
else
  ver=$("$B" --version 2>&1 | head -1 | tr -d '\r')
  echo "FAIL blender self test exit=$rc version=[$ver] files=$(find "$T/blender" -type f 2>/dev/null | wc -l): $(grep -aiE 'error|traceback|exception' "$log" | tail -2 | tr '\n' ' ' | cut -c1-300) last: $(tail -2 "$log" | tr -d '\r' | tr '\n' ' ' | cut -c1-200)"; exit 1
fi
