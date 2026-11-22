# Starts the art runner under its supervisor (restarts it after a crash until the queue is FINISHED), fully detached
# (WMI-created, so it survives this console and the Claude session closing).
Remove-Item D:\projects\hh_art\STOP -ErrorAction SilentlyContinue
$running = Get-CimInstance Win32_Process -Filter "Name like 'pythonw%'" | Where-Object { $_.CommandLine -like '*hh_art\supervise.py*' }
if ($running) { "supervisor already running (pid $($running[0].ProcessId))"; return }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
  CommandLine = '"D:\projects\hh_art\venv\Scripts\pythonw.exe" "D:\projects\hh_art\supervise.py"'
  CurrentDirectory = 'D:\projects\hh_art' }
"started supervisor pid $($r.ProcessId) (rc $($r.ReturnValue))"
