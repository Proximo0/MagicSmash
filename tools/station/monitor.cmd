@echo off
rem Double-click to watch all four station PCs. Read-only; close the window to stop.
title Horde and Hearth stations
set "B="
for %%p in ("%GIT_BASH%" "C:\Program Files\Git\bin\bash.exe" "C:\projects\tools\PortableGit\bin\bash.exe" "D:\projects\tools\PortableGit\bin\bash.exe") do if not defined B if exist %%p set "B=%%~p"
if not defined B (echo Git Bash not found. Install Git for Windows or set GIT_BASH. & pause & exit /b 1)
mode con: cols=150 lines=50 >nul 2>&1
"%B%" "%~dp0monitor.sh" %*
pause
