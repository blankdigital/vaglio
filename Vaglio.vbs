' Avvia Vaglio senza finestra di console, né cmd né PowerShell visibili.
' Doppio clic su questo file, oppure sul collegamento sul Desktop.
Option Explicit
Dim fso, sh, cartella, comando
Set fso = CreateObject("Scripting.FileSystemObject")
cartella = fso.GetParentFolderName(WScript.ScriptFullName)
comando = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & cartella & "\vaglio-gui.ps1"""
Set sh = CreateObject("WScript.Shell")
sh.Run comando, 0, False
