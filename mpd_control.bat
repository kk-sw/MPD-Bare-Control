@echo off
::powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mpd_control.ps1" "192.168.1.CHANGE_ME"
powershell -File "%~dp0mpd_control.ps1" "192.168.1.CHANGE_ME"
