#!/usr/bin/env bash
# A queue `shell` job: the GitHub Actions runner on this PC comes back after a restart, and is started now if it is not
# running. Windows: under the user's own account (not a service: a service account cannot see cargo or the graphics
# card), by one small .cmd in the user's Startup folder. Linux: the runner's own service if it is installed (svc.sh),
# else a crontab @reboot line of this user. Nothing is elevated, no password is stored. Safe to re-run.
#   queue.sh add kind=shell args=script=runnerstart needs=<machine> priority=9
find_dir() {  # $1 = the start script's name; a folder holding it beside the .runner registration
	local d f
	# A runner that is running says where it lives (one was set up in C:\Windows\System32\actions-runner).
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*) d=$(powershell.exe -NoProfile -Command "(Get-Process Runner.Listener -ErrorAction SilentlyContinue | Select-Object -First 1).Path" 2>/dev/null | tr -d '\r') ; [ -n "$d" ] && d=$(cygpath -u "$d" 2>/dev/null) ;;
	*) d=$(pgrep -f Runner.Listener 2>/dev/null | head -1); [ -n "$d" ] && d=$(readlink "/proc/$d/exe" 2>/dev/null) ;;
	esac
	if [ -n "$d" ]; then d=$(dirname "$(dirname "$d")"); [ -f "$d/$1" ] && [ -f "$d/.runner" ] && { echo "$d"; return 0; }; fi
	for d in "$HOME/actions-runner" /c/actions-runner /d/actions-runner /c/projects/actions-runner /d/projects/actions-runner "$HOME/projects/actions-runner" "$HOME/Downloads/actions-runner" /c/runner /d/runner /opt/actions-runner /c/Windows/System32/actions-runner; do
		[ -f "$d/$1" ] && [ -f "$d/.runner" ] && { echo "$d"; return 0; }
	done
	for f in "$HOME"/*/"$1" "$HOME"/*/*/"$1" /c/*/"$1" /d/*/"$1"; do
		[ -f "$f" ] && [ -f "$(dirname "$f")/.runner" ] && { dirname "$f"; return 0; }
	done
	return 1
}
case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*)
	dir=$(find_dir run.cmd) || { echo "FAIL runnerstart no registered runner folder found (run.cmd beside .runner)"; exit 1; }
	start="$APPDATA/Microsoft/Windows/Start Menu/Programs/Startup"
	[ -d "$start" ] || { echo "FAIL runnerstart no Startup folder at $start"; exit 1; }
	win=$(cygpath -w "$dir")
	printf '@echo off\r\nrem Starts the GitHub Actions runner at login (written by tools/station/jobs/runnerstart.sh).\r\ncd /d "%s"\r\nstart "github-runner" /min cmd /c run.cmd\r\n' "$win" >"$start/github-runner.cmd" || { echo "FAIL runnerstart could not write the Startup entry"; exit 1; }
	up() { tasklist.exe 2>/dev/null | grep -qi "Runner.Listener"; }
	started=no
	if ! up; then
		MSYS_NO_PATHCONV=1 cmd.exe /c "$(cygpath -w "$start/github-runner.cmd")" >/dev/null 2>&1
		for _ in 1 2 3 4 5 6; do sleep 5; up && break; done
		started=yes
	fi
	if up; then echo "PASS runnerstart folder=$win at_login=startup-entry running=yes started_now=$started"
	else echo "FAIL runnerstart folder=$win at_login=startup-entry but the runner did not start (run.cmd by hand shows why)"; exit 1; fi
	;;
*)
	dir=$(find_dir run.sh) || { echo "FAIL runnerstart no registered runner folder found (run.sh beside .runner)"; exit 1; }
	up() { pgrep -f "Runner.Listener" >/dev/null 2>&1; }
	if systemctl list-units --type=service --all 2>/dev/null | grep -q "actions\.runner\..*\.service" && systemctl is-enabled "$(systemctl list-units --type=service --all 2>/dev/null | grep -o 'actions\.runner\.[^ ]*\.service' | head -1)" >/dev/null 2>&1; then
		how=service
	else
		line="@reboot cd $dir && nohup ./run.sh >>$dir/runner.log 2>&1 &"
		crontab -l 2>/dev/null | grep -qF "$dir && nohup ./run.sh" || { (crontab -l 2>/dev/null; echo "$line") | crontab - || { echo "FAIL runnerstart could not add the crontab line"; exit 1; }; }
		how=crontab
	fi
	started=no
	if ! up && [ "$how" = crontab ]; then
		(cd "$dir" && setsid nohup ./run.sh >>"$dir/runner.log" 2>&1 &)
		for _ in 1 2 3 4 5 6; do sleep 5; up && break; done
		started=yes
	fi
	if up; then echo "PASS runnerstart folder=$dir at_login=$how running=yes started_now=$started"
	else echo "FAIL runnerstart folder=$dir at_login=$how but the runner is not running (service: sudo ./svc.sh start in $dir)"; exit 1; fi
	;;
esac
