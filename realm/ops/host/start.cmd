@echo off
rem Starts the realm and keeps it up (restarts the gateway if it dies). Double-click, or run from a console.
rem Everything is set in ops.conf. Stop with stop.cmd. Logs are in the logs folder.
cd /d "%~dp0"
for /f %%v in (current) do set CUR=%%v
"%~dp0releases\%CUR%\realm-ops.exe" run --root="%~dp0."
