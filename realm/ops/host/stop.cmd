@echo off
cd /d "%~dp0"
for /f %%v in (current) do set CUR=%%v
"%~dp0releases\%CUR%\realm-ops.exe" stop --root="%~dp0."
