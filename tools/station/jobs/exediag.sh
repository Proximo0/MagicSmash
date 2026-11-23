#!/usr/bin/env bash
# Queue `shell` job: why can this PC not start a program it built? (The laptop failed queue jobs on 23 Nov 2026 with
# "timeout: failed to run command 'realm/target/release/realm-soak': Permission denied".) Reads only; changes nothing,
# and touches no security setting. The full report is published as <machine>-exediag.txt.
#   queue.sh add kind=shell args=script=exediag needs=<machine> priority=9
# station-sac: ok   (this diagnosis is meant to run where Smart App Control is on; q_ownbin lets it)
art="${STATION_JOB_ART:-${TMPDIR:-/tmp}}"; m="${MACHINE:-${STATION_NAME:-$(hostname)}}"; out="$art/$m-exediag.txt"
mkdir -p "$art" 2>/dev/null
ok=0; bad=0; first=""
{
  echo "--- files in realm/target/release and realm/store/target/release (newest first)"
  ls -lat --time-style=long-iso realm/target/release/ realm/store/target/release/ 2>&1 | grep -v '^d' | head -40
  echo "--- same names without .exe (a stray file would be tried first)"
  for n in realm-soak realm-loadtest realm-economy realm-server realm-ops; do [ -e "realm/target/release/$n" ] && ls -la "realm/target/release/$n"; done
  echo "--- start each program (10 s limit; a usage error is fine, 126 is the fault)"
  for f in realm/target/release/realm-loadtest realm/target/release/realm-soak realm/target/release/realm-economy realm/store/target/release/realm-store; do
    msg=$(timeout -k 5 10 "$f" --help 2>&1); rc=$?; msg=$(head -2 <<<"$msg" | tr '\n' ' ' | cut -c1-200)
    echo "rc=$rc $f: $msg"
    if [ "$rc" = 126 ] || [ "$rc" = 127 ]; then bad=$((bad + 1)); [ -n "$first" ] || first="$(basename "$f") rc=$rc"; else ok=$((ok + 1)); fi
  done
  case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    echo "--- still running from earlier jobs"
    tasklist.exe 2>/dev/null | grep -i '^realm' | head -20
    echo "--- security state and recent blocks (read only)"
    ps1='try { Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled,SmartAppControlState,IsTamperProtected,AntivirusEnabled | Format-List | Out-String } catch { "Get-MpComputerStatus: " + $_.Exception.Message }
try { (Get-MpPreference).EnableControlledFolderAccess | ForEach-Object { "ControlledFolderAccess=" + $_ } } catch { "Get-MpPreference: " + $_.Exception.Message }
try { Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | ForEach-Object { "antivirus=" + $_.displayName } } catch { "SecurityCenter2: " + $_.Exception.Message }
foreach ($l in "Microsoft-Windows-Windows Defender/Operational","Microsoft-Windows-CodeIntegrity/Operational","Microsoft-Windows-AppLocker/EXE and DLL") {
  "--- log " + $l
  try { Get-WinEvent -LogName $l -MaxEvents 400 -ErrorAction Stop | Where-Object { $_.TimeCreated -gt (Get-Date).AddHours(-3) -and $_.Message -match "realm|target|Blocked|blocked|prevented" } | Select-Object -First 12 | ForEach-Object { "{0:u} id={1} {2}" -f $_.TimeCreated, $_.Id, (($_.Message -replace "\s+"," ").Substring(0, [Math]::Min(300, $_.Message.Length))) } } catch { "  " + $_.Exception.Message }
}'
    timeout -k 5 120 powershell.exe -NoProfile -NonInteractive -Command "$ps1" 2>&1 | tr -d '\r'
    ;;
  esac
} >"$out" 2>&1
sac=$(grep -m1 -o 'SmartAppControlState *: *[A-Za-z]*' "$out" | tr -d ' '); av=$(grep -m1 '^antivirus=' "$out" | cut -c1-60)
blocks=$(grep -c ' id=' "$out")
if [ "$bad" = 0 ]; then echo "PASS exediag started=$ok blocked=0 ${sac:-} ${av:-} log_lines=$blocks (report $m-exediag.txt)"
else echo "FAIL exediag started=$ok blocked=$bad first=[$first] ${sac:-} ${av:-} log_lines=$blocks (report $m-exediag.txt)"; exit 1; fi
