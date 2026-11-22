#!/bin/sh
# Any realm-ops command: ./ops.sh status | backup | backups | drill | restore | releases | install DIR | switch V | rollback
root=$(cd "$(dirname "$0")" && pwd)
exec "$root/releases/$(cat "$root/current")/realm-ops" "$@" --root="$root"
