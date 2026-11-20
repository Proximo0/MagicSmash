@echo off
rem Sends one test message to Sentry, to check that this build can report crashes (docs/sentry.md).
start "" "%~dp0Four-of-Wands.exe" -- --sentry-test
