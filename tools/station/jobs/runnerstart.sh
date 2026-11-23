#!/usr/bin/env bash
# A queue `shell` job: makes the GitHub Actions runner on this Windows PC start at login, under the user's own account
# (not a service: a service account cannot see cargo or the graphics card). It writes one small .cmd into the user's
# Startup folder that starts the runner's run.cmd minimised. Linux runners are services already (svc.sh): nothing to do.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *) echo "PASS runnerstart not Windows: the runner is a service here"; exit 0 ;; esac
dir=""
for d in /c/actions-runner /d/actions-runner "$HOME/actions-runner" /c/projects/actions-runner /d/projects/actions-runner "$HOME/Downloads/actions-runner" /c/runner /d/runner; do
	[ -f "$d/run.cmd" ] && [ -f "$d/.runner" ] && { dir=$d; break; }
done
if [ -z "$dir" ]; then
	# One level under the drive roots and the home folder: a folder holding both run.cmd and the .runner registration.
	for f in /c/*/run.cmd /d/*/run.cmd "$HOME"/*/run.cmd; do
		[ -f "$f" ] && [ -f "$(dirname "$f")/.runner" ] && { dir=$(dirname "$f"); break; }
	done
fi
[ -n "$dir" ] || { echo "FAIL runnerstart no registered runner folder found (looked for run.cmd beside .runner)"; exit 1; }
start="$APPDATA/Microsoft/Windows/Start Menu/Programs/Startup"
[ -d "$start" ] || { echo "FAIL runnerstart no Startup folder at $start"; exit 1; }
win=$(cygpath -w "$dir")
printf '@echo off\r\nrem Starts the GitHub Actions runner at login (written by tools/station/jobs/runnerstart.sh).\r\ncd /d "%s"\r\nstart "github-runner" /min cmd /c run.cmd\r\n' "$win" >"$start/github-runner.cmd" || { echo "FAIL runnerstart could not write the Startup entry"; exit 1; }
running=no; tasklist.exe 2>/dev/null | grep -qi "Runner.Listener" && running=yes
echo "PASS runnerstart folder=$win startup_entry=yes running_now=$running"
