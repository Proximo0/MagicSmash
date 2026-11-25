@echo off
rem Horde & Hearth playtest: finds the live server on the Linux PC and starts the game. See README.txt.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1"
if errorlevel 1 pause
