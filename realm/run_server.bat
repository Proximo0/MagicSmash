@echo off
rem Starts the realm server for test hosting on this PC: UDP port 7777, 200 bots, 8 000 monsters, a report
rem line every 10 seconds. Extra flags pass through, for example: run_server.bat --bots=500 --threads=4
rem Players on this network connect to this PC's local address (ipconfig shows it, e.g. 192.168.1.20:7777);
rem friends elsewhere need UDP 7777 forwarded to this PC on the router. See realm\README.md.
cd /d "%~dp0"
set EXE=realm-server.exe
if not exist "%EXE%" set EXE=target\release\realm-server.exe
if not exist "%EXE%" (
    echo realm-server.exe was not found next to this file or in target\release.
    echo Build it with: cargo build --release   or take it from the CI artifact realm-server-windows.
    pause
    exit /b 1
)
"%EXE%" --port=7777 --bots=200 --monsters=8000 --threads=2 --report=10 %*
echo.
echo The server stopped (exit code %ERRORLEVEL%).
pause
