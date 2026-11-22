HORDE & HEARTH realm host folder
================================
ops.conf        every setting, documented; edit, then restart
releases\V\     the programs of one build (realm-gateway, realm-server, realm-ops, realm-store) and release.txt
current         the release that runs (a text file: its version)     previous   the one before it
data\           the store (realm.db) and its side files             backups\   verified online backups
logs\           realm.log (rotated), supervisor.log, console.log

Windows: start.cmd (or start.ps1) runs and keeps up the realm; stop.cmd stops it; install-task.ps1 starts it at logon.
Linux:   realm.service for systemd (see its header), or ./start.sh.
Every day: ops status   (the status page), ops backups, ops drill.
Release:   ops install C:\path\to\release-folder ; ops switch V ; restart
Rollback:  ops rollback ; restart          (refused if the store moved to a newer schema:
           stop, `ops rollback --restore-pre-switch`, start; play since the switch is lost)
Restore:   stop the realm ; ops restore [backup-file] ; start the realm
Kill switches: ops kill login | trade | market | field N | all ; ops revive ... ; ops switches   (they survive a restart)
Full manual: docs/realm/ops.md
