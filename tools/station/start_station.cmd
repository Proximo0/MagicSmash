@echo off
rem Windows station launcher (Task Scheduler, at log on). Runs Git Bash's station.sh and restarts it whenever it stops,
rem with one line in station_restarts.log saying when and with which exit code. Set GIT_BASH if Git is not in C:\Program Files\Git.
setlocal
if "%GIT_BASH%"=="" set "GIT_BASH=C:\Program Files\Git\bin\bash.exe"
cd /d "%~dp0\..\.."
:loop
"%GIT_BASH%" -lc "tools/station/station.sh --watch idle"
echo %date% %time% station.sh stopped with exit code %errorlevel%, restarting in 60 s>>station_restarts.log
timeout /t 60 /nobreak >nul
goto loop
