#!/usr/bin/env bash
# Queue `shell` job: download one named file from tools/station/assets.txt to the job's artifacts, for things the
# cloud cannot reach (asset sites refuse its proxy). It only saves the file; nothing downloaded is run.
# assets.txt lines: <name> <https url> (the licence of each is noted beside it). Summary line: name, bytes, sha256.
# Queue it: queue.sh add kind=shell args="script=fetchasset name=<name>" needs=linux
set -uo pipefail
name=""; for w in "$@"; do case "$w" in name=*) name=${w#name=} ;; esac; done
here=$(cd "$(dirname "$0")/.." && pwd)
url=$(awk -v n="$name" '$1==n && $2 ~ /^https:\/\//{print $2; exit}' "$here/assets.txt")
[ -n "$url" ] || { echo "fetchasset FAILED: no asset named '$name' in assets.txt"; exit 1; }
art="${STATION_JOB_ART:-${TMPDIR:-/tmp}}"; mkdir -p "$art"
out="$art/asset-$name"
curl -fsSL --max-time 600 --max-filesize 60000000 -A "Mozilla/5.0" -o "$out" "$url" || { echo "fetchasset FAILED: $name could not be downloaded"; exit 1; }
if head -c 512 "$out" | tr -d '\r\n\t ' | grep -qiE '^(<!doctype|<html)'; then   # a web page (quota, sign-in, error) instead of the file
  echo "fetchasset FAILED: $name came back as a web page: $(grep -oiE '<title>[^<]*' "$out" | head -1 | cut -c8-100)"; rm -f "$out"; exit 1
fi
echo "fetchasset ok name=$name bytes=$(wc -c <"$out" | tr -d ' ') sha256=$(sha256sum "$out" | cut -c1-16)"
