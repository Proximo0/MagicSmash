@echo off
rem Any realm-ops command: ops status | backup | backups | drill | restore | releases | install DIR | switch V | rollback ...
cd /d "%~dp0"
for /f %%v in (current) do set CUR=%%v
"%~dp0releases\%CUR%\realm-ops.exe" %* --root="%~dp0."
