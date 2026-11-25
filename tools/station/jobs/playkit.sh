#!/usr/bin/env bash
# Queue `shell` job: a "Play Horde and Hearth" launcher on THIS station's desktop, so Curtis can play on any of the four
# PCs (25 Nov 2026: "make sure i can log in on all four pcs if i want to for playtesting").
# Builds our native module, copies the client to ~/HordeAndHearthPlay (outside the station checkout, so a merge never
# touches a running game), imports it, and writes the launcher, which runs realm/playtest/play.ps1 (Windows) or play.sh
# (Linux): find the live LAN server (station job lanhost), trust its certificate, start the game with this station's
# Godot (a debug binary, so --dev-cert is honoured). Re-run to update to the newest main. Changes no system setting.
#   queue.sh add kind=shell args=script=playkit needs=<machine> priority=9
# Last line: PASS playkit dest=.. launcher=..  or FAIL playkit <reason>.
set -u
[ -n "${STATION_QUEUE_STUB:-}" ] && { echo "PASS playkit stub"; exit 0; }
command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
command -v cargo >/dev/null 2>&1 || { echo "FAIL playkit cargo is not installed on this station"; exit 1; }
win=""; case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) win=1; lib=realm_godot.dll ;; *) lib=librealm_godot.so ;; esac
gp=$(command -v "${GODOT:-godot}" 2>/dev/null) || { echo "FAIL playkit no Godot (GODOT=${GODOT:-unset})"; exit 1; }
case "$gp" in *_console.exe) [ -f "${gp%_console.exe}.exe" ] && gp="${gp%_console.exe}.exe" ;; esac   # the windowed one
log="${STATION_JOB_ART:-${TMPDIR:-/tmp}}/playkit_build.log"; mkdir -p "$(dirname "$log")"
( cd realm/godot && timeout -k 30 3600 cargo build --release -j2 -q ) >"$log" 2>&1 || { echo "FAIL playkit build: $(tail -2 "$log" | tr '\n' ' ' | cut -c1-160)"; exit 1; }
dest="$HOME/HordeAndHearthPlay"; mkdir -p "$dest"; rm -rf "$dest/client.new"
cp -r realm/client "$dest/client.new" && rm -rf "$dest/client.new/.godot" && mkdir -p "$dest/client.new/bin" \
  && cp "realm/godot/target/release/$lib" "$dest/client.new/bin/" || { echo "FAIL playkit copy to $dest"; exit 1; }
rm -rf "$dest/client" 2>/dev/null; [ -e "$dest/client" ] && { echo "FAIL playkit $dest/client is in use (close the game, then re-run)"; exit 1; }
mv "$dest/client.new" "$dest/client"
( timeout -k 30 300 "$gp" --headless --path "$dest/client" --import || timeout -k 30 300 "$gp" --headless --path "$dest/client" --import ) >>"$log" 2>&1 || true
[ -d "$dest/client/.godot" ] || { echo "FAIL playkit the import made no .godot folder"; exit 1; }
cp realm/playtest/play.sh realm/playtest/play.ps1 realm/playtest/README.txt "$dest/"
if [ -n "$win" ]; then
  desk=$(MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" 2>/dev/null | tr -d '\r')
  [ -n "$desk" ] || { echo "FAIL playkit no Desktop folder"; exit 1; }
  launcher="$(cygpath -u "$desk")/Play Horde and Hearth.cmd"
  printf '@echo off\r\nrem Horde & Hearth playtest (station job playkit). Re-run the job to update.\r\npowershell -NoProfile -ExecutionPolicy Bypass -File "%s" -Godot "%s" -Project "%s"\r\nif errorlevel 1 pause\r\n' \
    "$(cygpath -w "$dest/play.ps1")" "$(cygpath -w "$gp")" "$(cygpath -w "$dest/client")" >"$launcher" || { echo "FAIL playkit cannot write $launcher"; exit 1; }
else
  desk=$(xdg-user-dir DESKTOP 2>/dev/null); [ -n "$desk" ] && [ "$desk" != "$HOME" ] || desk="$HOME/Desktop"; mkdir -p "$desk"
  launcher="$desk/horde-and-hearth.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Play Horde and Hearth\nComment=Playtest against the LAN server (station job playkit)\nExec=env GODOT=%s bash %s\nTerminal=true\nCategories=Game;\n' "$gp" "$dest/play.sh" >"$launcher"
  chmod +x "$launcher"; command -v gio >/dev/null 2>&1 && gio set "$launcher" metadata::trusted true 2>/dev/null
  mkdir -p "$HOME/.local/share/applications" && cp "$launcher" "$HOME/.local/share/applications/"
fi
echo "PASS playkit dest=$dest launcher=$launcher godot=$gp"
