#!/usr/bin/env bash
# Queue `shell` job: make THIS station fit to run day and night (Curtis, 22 Nov 2026: "i can have these running 24/7.
# make sure they are ready to go with power settings etc adjusted"). On mains power only: never sleep, never hibernate,
# no disk spin-down, closing a laptop lid does nothing; the screen may still turn off. Battery settings are left alone.
# It changes only what an ordinary user may change, tries the admin-only parts without prompting, and reports what is
# left. Safe to run again. Queue it once per machine: queue.sh add kind=shell args=script=power needs=<machine> priority=9
did="" left=""
ok() { did="$did $1"; }
no() { left="$left $1"; }

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    pc() { MSYS_NO_PATHCONV=1 powercfg.exe "$@" >/dev/null 2>&1; }
    pc /change standby-timeout-ac 0 && ok sleep=never || no sleep-timeout
    pc /change hibernate-timeout-ac 0 && ok hibernate=never || no hibernate-timeout
    pc /change disk-timeout-ac 0 && ok disk=never || no disk-timeout
    # lid close and the sleep button do nothing on mains; hybrid sleep and wake timers stay out of the way
    pc /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 && ok lid=nothing || no lid-action
    pc /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0 && ok sleepbutton=nothing || no sleep-button
    pc /setacvalueindex SCHEME_CURRENT SUB_SLEEP HYBRIDSLEEP 0 || true
    pc /setactive SCHEME_CURRENT || no apply-scheme
    pc /hibernate off && ok hibernate=off || no "hibernate-off(admin)"
    # does the station come back after a restart (Windows Update restarts PCs on its own)?
    start="$APPDATA/Microsoft/Windows/Start Menu/Programs/Startup"
    if ls "$start" 2>/dev/null | grep -qi station || MSYS_NO_PATHCONV=1 schtasks.exe /query /fo csv 2>/dev/null | grep -qi station; then
      ok autostart=yes
    else no "autostart(no Startup entry or task named station)"; fi
    MSYS_NO_PATHCONV=1 powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>/dev/null | tr -d '\r' >"${STATION_JOB_ART:-.}/power_state.txt" 2>/dev/null || true
    ;;
  Linux)
    if command -v gsettings >/dev/null 2>&1; then
      s=org.gnome.settings-daemon.plugins.power
      gsettings set $s sleep-inactive-ac-type nothing 2>/dev/null && gsettings set $s sleep-inactive-ac-timeout 0 2>/dev/null && ok sleep=never || no "desktop-sleep-setting"
    fi
    # machine-wide: no sleep targets, lid ignored on mains. Needs sudo without a password prompt; never asks.
    if sudo -n true 2>/dev/null; then
      sudo -n systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 && ok sleep-targets=masked || no sleep-targets
      sudo -n mkdir -p /etc/systemd/logind.conf.d &&
        printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\nIdleAction=ignore\n' |
        sudo -n tee /etc/systemd/logind.conf.d/50-station.conf >/dev/null && ok lid=nothing-after-next-login || no lid-action
    else
      [ "$(systemctl is-enabled sleep.target 2>/dev/null)" = masked ] && ok sleep-targets=masked || no "sleep-targets(sudo)"
      grep -rqs '^HandleLidSwitch=ignore' /etc/systemd/logind.conf /etc/systemd/logind.conf.d 2>/dev/null && ok lid=nothing || no "lid-action(sudo)"
    fi
    if crontab -l 2>/dev/null | grep -q station || systemctl --user list-unit-files 2>/dev/null | grep -qi station; then ok autostart=yes
    else no "autostart(no crontab line or user service named station)"; fi
    ;;
  *) echo "INFO power: unknown system $(uname -s), nothing changed"; exit 0 ;;
esac

if [ -z "$left" ]; then echo "PASS power set:$did"; else echo "INFO power set:$did; NOT set:$left"; fi
