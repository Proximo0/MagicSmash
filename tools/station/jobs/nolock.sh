#!/usr/bin/env bash
# Queue `shell` job: on mains power THIS station never locks, never asks for sign-in after idling and never drops into
# standby (Curtis, 22 Nov 2026: "we dont need any interference in our game this is priority number one on all four
# pcs"). Found on the Ryzen laptop: with Modern Standby (S0) "display off after 10 min" put the PC into standby although
# sleep was "never", and waking it showed the sign-in screen. power.sh sets sleep/hibernate/lid; this adds the rest.
# Only what the signed-in user may change, no elevation prompt, no password stored, no automatic sign-in. Safe to re-run.
#   queue.sh add kind=shell args=script=nolock needs=<machine> priority=9
did="" left=""
ok() { did="$did $1"; }
no() { left="$left $1"; }
art="${STATION_JOB_ART:-.}/nolock_state.txt"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    pc() { MSYS_NO_PATHCONV=1 powercfg.exe "$@" >/dev/null 2>&1; }
    rg() { MSYS_NO_PATHCONV=1 reg.exe add "$1" /v "$2" /t "$3" /d "$4" /f >/dev/null 2>&1; }
    pc /change monitor-timeout-ac 0 && ok display=never || no display-timeout
    pc /change standby-timeout-ac 0 && ok sleep=never || no sleep-timeout
    pc /change hibernate-timeout-ac 0 && ok hibernate=never || no hibernate-timeout
    pc /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 && ok lid=nothing || no lid-action
    pc /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 && ok wake-signin=off || no "wake-signin(admin: powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 0)"
    pc /setactive SCHEME_CURRENT || no apply-scheme
    d='HKCU\Control Panel\Desktop'
    rg "$d" ScreenSaveActive REG_SZ 0 && rg "$d" ScreenSaverIsSecure REG_SZ 0 && ok screensaver-lock=off || no screensaver-lock
    rg "$d" DelayLockInterval REG_DWORD 4294967295 && ok away-signin=never || no away-signin
    rg 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' EnableGoodbye REG_DWORD 0 && ok dynamic-lock=off || no dynamic-lock
    start="$APPDATA/Microsoft/Windows/Start Menu/Programs/Startup"
    if ls "$start" 2>/dev/null | grep -qi station || MSYS_NO_PATHCONV=1 schtasks.exe /query /fo csv 2>/dev/null | grep -qi station; then
      ok autostart=yes
    else no "autostart(no Startup entry or task named station)"; fi
    {
      MSYS_NO_PATHCONV=1 powercfg.exe /a
      MSYS_NO_PATHCONV=1 powercfg.exe /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE
      MSYS_NO_PATHCONV=1 reg.exe query "$d" /v DelayLockInterval
      MSYS_NO_PATHCONV=1 reg.exe query 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v InactivityTimeoutSecs
    } 2>&1 | tr -d '\r' >"$art" 2>/dev/null || true
    grep -q InactivityTimeoutSecs.*0x[1-9a-f] "$art" 2>/dev/null && no "machine-inactivity-limit(set by policy, admin)"
    ;;
  Linux)
    if command -v gsettings >/dev/null 2>&1; then
      gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null && ok screen-lock=off || no screen-lock
      gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null && ok blank=never || no idle-delay
      gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend false 2>/dev/null || true
      s=org.gnome.settings-daemon.plugins.power
      gsettings set $s sleep-inactive-ac-type nothing 2>/dev/null && ok sleep=never || no desktop-sleep-setting
    else no "desktop-settings(no gsettings)"; fi
    [ "$(systemctl is-enabled sleep.target 2>/dev/null)" = masked ] && ok sleep-targets=masked || no "sleep-targets(sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target)"
    if crontab -l 2>/dev/null | grep -q station || systemctl --user list-unit-files 2>/dev/null | grep -qi station; then ok autostart=yes
    else no "autostart(no crontab line or user service named station)"; fi
    { gsettings get org.gnome.desktop.screensaver lock-enabled; gsettings get org.gnome.desktop.session idle-delay; } >"$art" 2>&1 || true
    ;;
  *) echo "INFO nolock: unknown system $(uname -s), nothing changed"; exit 0 ;;
esac

if [ -z "$left" ]; then echo "PASS nolock set:$did"; else echo "INFO nolock set:$did; NOT set:$left"; fi
