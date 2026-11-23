#!/bin/bash
# Records gameplay clips of the field client: usage record.sh <out dir>. Needs godot, ffmpeg, Xvfb and the built
# realm-server and module. One clip per line of CLIPS ("field zoom secs class race"), then all joined as video.mp4.
set -u
out="$1"; mkdir -p "$out"; out=$(cd "$out" && pwd)
cd "$(dirname "$0")/../.."
W="${VIDEO_W:-960}"; H="${VIDEO_H:-540}"; FPS="${VIDEO_FPS:-30}"
CLIPS="${CLIPS:-0 2 16 0 0;2 2 16 2 1;2 1 12 3 0;3 2 16 1 3;5 2 18 4 2}"
export DISPLAY=:97
# Without a window manager the client window keeps the project size, 960x540, at the middle of the screen: the
# screen is that size, and the clip is doubled with hard pixels.
Xvfb :97 -screen 0 "${W}x${H}x24" >/dev/null 2>&1 &
xv=$!
sleep 2
n=0
IFS=';' read -ra clips <<<"$CLIPS"
for c in "${clips[@]}"; do
	read -r field zoom secs class race <<<"$c"
	n=$((n + 1)); port=$((7830 + n))
	realm/target/release/realm-server --port=$port --field="$field" --bots=300 --monsters=8000 --rally=0.3 --threads=2 --report=600 >"$out/server$n.log" 2>&1 &
	sv=$!
	sleep 4
	godot --path realm/client -- --server=127.0.0.1:$port --bot --zoom="$zoom" --class="$class" --race="$race" --window="${W}x${H}" --debug=0 --mute >"$out/client$n.log" 2>&1 &
	cl=$!
	sleep 12  # join and settle
	ffmpeg -loglevel error -y -f x11grab -draw_mouse 0 -framerate "$FPS" -video_size "${W}x${H}" -i :97 -t "$secs" -vf "scale=iw*2:ih*2:flags=neighbor" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p "$out/clip$n.mp4"
	kill "$cl" "$sv" 2>/dev/null; wait "$cl" "$sv" 2>/dev/null
	echo "file 'clip$n.mp4'" >>"$out/list.txt"
	grep -ciE "error" "$out/client$n.log" | sed "s/^/clip $n client error lines: /"
done
kill "$xv" 2>/dev/null
(cd "$out" && ffmpeg -loglevel error -y -f concat -i list.txt -c copy video.mp4)
ls -la "$out"
