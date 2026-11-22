@echo off
rem Restarts the gateway so it runs the release `current` points at (after switch.cmd).
cd /d "%~dp0"
for /f %%v in (current) do set CUR=%%v
"%~dp0releases\%CUR%\realm-ops.exe" restart --root="%~dp0."
