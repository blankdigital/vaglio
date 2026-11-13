@echo off
rem Apre l'interfaccia grafica di Vaglio senza finestra di console.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0vaglio-gui.ps1"
