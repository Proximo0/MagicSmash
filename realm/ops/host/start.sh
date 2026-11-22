#!/bin/sh
# Starts the realm in the foreground (use realm.service for a real box). Stop: ./ops.sh stop
root=$(cd "$(dirname "$0")" && pwd)
exec "$root/releases/$(cat "$root/current")/realm-ops" run --root="$root"
