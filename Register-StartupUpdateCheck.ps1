param(
    [string]$TaskName = "Codex Background Update Check"
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "StartupUpdateCheck.ps1"
$launcherPath = Join-Path $PSScriptRoot "RunStartupUpdateCheck.vbs"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Cannot find $scriptPath"
}
if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Cannot find $launcherPath"
}

$oldTaskName = "Codex Startup Update Check"
Unregister-ScheduledTask -TaskName $oldTaskName -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$escapedLauncherPath = [System.Security.SecurityElement]::Escape($launcherPath)
$userId = "{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME
$escapedUserId = [System.Security.SecurityElement]::Escape($userId)

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Silently updates Windows, drivers, Microsoft Store apps, WinGet packages, NVIDIA, Armoury Crate, Steam, Epic Games, and other gaming launchers after Wi-Fi connects. Never restarts Windows automatically.</Description>
  </RegistrationInfo>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"&gt;&lt;Select Path="Microsoft-Windows-NetworkProfile/Operational"&gt;*[System[(EventID=10000)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$escapedUserId</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>%SystemRoot%\System32\wscript.exe</Command>
      <Arguments>//B //NoLogo &quot;$escapedLauncherPath&quot;</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$xmlPath = Join-Path $env:TEMP "Codex-Background-Update-Check.xml"
$taskXml | Set-Content -LiteralPath $xmlPath -Encoding Unicode

try {
    schtasks.exe /Create /TN $TaskName /XML $xmlPath /F | Out-Null
} finally {
    Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Registered scheduled task: $TaskName"
Write-Host "Trigger: Wi-Fi/network connection event (runs only after Wi-Fi is confirmed)"
Write-Host "Hidden launcher: $launcherPath"
