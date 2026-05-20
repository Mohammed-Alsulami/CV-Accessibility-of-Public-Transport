@echo off
REM Windows launcher for Accessibility Audit Tool
REM Usage: double-click this file OR run: .\start_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_windows.ps1"

pause
