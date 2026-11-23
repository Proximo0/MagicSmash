#!/bin/bash
# Records gameplay clips of the field client: usage record.sh <out dir>. Needs godot, ffmpeg, Xvfb and the built
# realm-server and module. One clip per line of CLIPS ("field zoom secs class race"), then all joined as video.mp4.
set -u
out="$1"; mkdir -p "$out"; out=$(cd "$out" && pwd)
cd "$(dirname "$0")/../.."
W="${VIDEO_W:-1280}"; H="${VIDEO_H:-720}"; FPS="${VIDEO_FPS:-30}"
CLIPS="${CLIPS:-0 2 24 0 0;0 1 16 2 1;2 2 16 1 3;4 4 14 4 2}"
export DISPLAY=:97
# Godot shrinks a window as large as the screen to three quarters: the screen is a third larger, the window sits centred.
SW=$((W * 4 / 3)); SH=$((H * 4 / 3))
Xvfb :97 -screen 0 "${SW}x${SH}x24" >/dev/null 2>&1 &
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
	ffmpeg -loglevel error -y -f x11grab -draw_mouse 0 -framerate "$FPS" -video_size "${SW}x${SH}" -i :97 -t "$secs" -vf "crop=$W:$H" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p "$out/clip$n.mp4"
	kill "$cl" "$sv" 2>/dev/null; wait "$cl" "$sv" 2>/dev/null
	echo "file 'clip$n.mp4'" >>"$out/list.txt"
	grep -ciE "error" "$out/client$n.log" | sed "s/^/clip $n client error lines: /"
done
kill "$xv" 2>/dev/null
(cd "$out" && ffmpeg -loglevel error -y -f concat -i list.txt -c copy video.mp4)
ls -la "$out"
