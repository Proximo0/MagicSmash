#!/usr/bin/env bash
# Rebuild every icon, the contact sheet and the bag mock.  tools/char3d/build_icons.sh [KayKit gltf Assets dir]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
python3 "$here/build_icons.py" "$root/realm/client/art" ${1:+"$1"}
python3 "$here/icons_sheet.py" "$root/realm/client/art" "$root/work_review"
