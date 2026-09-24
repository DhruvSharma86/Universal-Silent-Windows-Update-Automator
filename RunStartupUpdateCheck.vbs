Option Explicit

Dim shell, folderPath, command

folderPath = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
command = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & folderPath & "\StartupUpdateCheck.ps1"" -RequireWifi -InstallUpdates"

Set shell = CreateObject("WScript.Shell")
shell.Run command, 0, False
WScript.Quit 0
