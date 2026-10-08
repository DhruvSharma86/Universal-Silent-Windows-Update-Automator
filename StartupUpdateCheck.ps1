<#
.SYNOPSIS
    Universal Silent Windows Update Automator
.DESCRIPTION
    Automatically updates Windows, drivers, Microsoft Store apps, WinGet packages,
    NVIDIA software, Armoury Crate, Steam, Epic Games, and other gaming launchers
    once per day when Wi-Fi is connected. Runs silently in background with no reports, no forced reboots.
#>

param(
    [switch]$RequireWifi,
    [switch]$InstallUpdates
)

$ErrorActionPreference = "Continue"

# ─── Constants ──────────────────────────────────────────────────────────────
$MUTEX_NAME      = "CodexBackgroundUpdateCheck"
$WIFI_CHECK_ID   = 9  # NdisPhysicalMedium 9 = Native 802.11
$PROCESS_TIMEOUT = 900  # 15 minutes default timeout (seconds)

# ─── Mutex ──────────────────────────────────────────────────────────────────
$updateMutex = New-Object System.Threading.Mutex($false, $MUTEX_NAME)
$hasUpdateMutex = $false
try {
    $hasUpdateMutex = $updateMutex.WaitOne(0)
} catch {
    exit 0
}
if (-not $hasUpdateMutex) { exit 0 }

# ─── Wi-Fi Check ────────────────────────────────────────────────────────────
if ($RequireWifi) {
    try {
        $connectedWifi = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
            $_.Status -eq "Up" -and $_.NdisPhysicalMedium -eq $WIFI_CHECK_ID
        }
        if (-not $connectedWifi) { exit 0 }
    } catch { }
}

# ─── Helper Functions ───────────────────────────────────────────────────────

function Invoke-WithTimeout {
    param(
        [ScriptBlock]$Action,
        [int]$TimeoutSeconds = $PROCESS_TIMEOUT,
        [string]$Name = "Process"
    )
    try {
        $job = Start-Job -ScriptBlock $Action
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
        if (-not $completed) {
            $job | Stop-Job -ErrorAction SilentlyContinue
            $job | Remove-Job -Force -ErrorAction SilentlyContinue
            return $false
        }
        $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
        $job | Remove-Job -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Find-ExistingPath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        $expanded = $ExecutionContext.InvokeCommand.ExpandString($candidate)
        $matches = @(Get-ChildItem -LiteralPath $expanded -ErrorAction SilentlyContinue)
        if ($matches.Count -gt 0) { return $matches[0].FullName }
    }
    return $null
}

function Test-ProcessRunning {
    param([string]$ProcessName)
    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    return $process -ne $null
}

function Start-SilentProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory = ""
    )
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $FilePath
        $startInfo.Arguments = ($Arguments -join " ")
        $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
        $process = [System.Diagnostics.Process]::Start($startInfo)
        return $process
    } catch {
        return $null
    }
}

# ─── Update Providers ───────────────────────────────────────────────────────

# Windows Update (preserved from original)
function Invoke-WindowsUpdate {
    if (-not $InstallUpdates) { return }
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $updates = @($result.Updates)
        if ($updates.Count -eq 0) { return }

        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($update in $updates) {
            if (-not $update.EulaAccepted) { $update.AcceptEula() }
            [void]$updatesToInstall.Add($update)
        }

        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $downloader.Download()

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installer.ForceQuiet = $true
        $installer.AllowSourcePrompts = $false
        $installResult = $installer.Install()
        # Intentionally ignore RebootRequired - never force restart
    } catch { }
}

# WinGet (preserved + improved)
function Invoke-WingetUpdates {
    if (-not $InstallUpdates) { return }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return }

    $outputPath = Join-Path $env:TEMP "codex-winget-$([guid]::NewGuid().ToString('N')).out"
    $errorPath  = Join-Path $env:TEMP "codex-winget-$([guid]::NewGuid().ToString('N')).err"
    try {
        $process = Start-Process -FilePath $winget.Source -ArgumentList @(
            "upgrade", "--all", "--include-unknown", "--silent", "--disable-interactivity",
            "--accept-source-agreements", "--accept-package-agreements"
        ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
        if (-not $process.WaitForExit(15 * 60 * 1000)) { $process.Kill() }
    } finally {
        Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
    }
}

# Microsoft Store (via WinGet Store source)
function Invoke-MicrosoftStoreUpdates {
    if (-not $InstallUpdates) { return }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return }

    try {
        # Check if msstore source is available
        $sources = & $winget.Source source list 2>$null
        if ($sources -and $sources -match 'msstore') {
            $outputPath = Join-Path $env:TEMP "codex-msstore-$([guid]::NewGuid().ToString('N')).out"
            $errorPath  = Join-Path $env:TEMP "codex-msstore-$([guid]::NewGuid().ToString('N')).err"
            $process = Start-Process -FilePath $winget.Source -ArgumentList @(
                "upgrade", "--all", "--source", "msstore", "--silent", "--disable-interactivity",
                "--accept-source-agreements", "--accept-package-agreements"
            ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
            if (-not $process.WaitForExit(15 * 60 * 1000)) { $process.Kill() }
            Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

# NVIDIA (via NVIDIA App if available)
function Invoke-NvidiaUpdates {
    if (-not $InstallUpdates) { return }

    # Detect NVIDIA GPU first
    $hasNvidia = $false
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -match "NVIDIA" }
        if ($gpu) { $hasNvidia = $true }
    } catch { }
    if (-not $hasNvidia) { return }

    # Try NVIDIA App (new unified app)
    $nvidiaApp = Find-ExistingPath -Candidates @(
        "$env:ProgramFiles\NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe",
        "$env:ProgramFiles\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe",
        "${env:ProgramFiles(x86)}\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"
    )

    if ($nvidiaApp) {
        # NVIDIA App/GeForce Experience handles driver updates automatically when running
        # Just ensure it's running to trigger its update check
        if (-not (Test-ProcessRunning -ProcessName "NVIDIA app")) {
            $proc = Start-SilentProcess -FilePath $nvidiaApp -Arguments @("-silent", "-autoupdate")
            if ($proc) {
                Start-Sleep -Seconds 30
                # Let it run in background to check for updates
            }
        }
    }
}

# Armoury Crate (ASUS)
function Invoke-ArmouryCrateUpdates {
    if (-not $InstallUpdates) { return }

    $armouryCrate = Find-ExistingPath -Candidates @(
        "$env:ProgramFiles\ASUS\ARMOURY CRATE Service\ArmouryCrate.UserSessionHelper.exe",
        "$env:ProgramFiles\WindowsApps\B9ECED6F.ArmouryCrate_*\ArmouryCrate.exe"
    )

    if ($armouryCrate) {
        # Armoury Crate updates itself via its service
        # Try to trigger update check if not running
        if (-not (Test-ProcessRunning -ProcessName "ArmouryCrate.UserSessionHelper")) {
            $proc = Start-SilentProcess -FilePath $armouryCrate -Arguments @()
            if ($proc) { Start-Sleep -Seconds 20 }
        }
    }
}

# Steam (improved - check if running first)
function Invoke-SteamUpdates {
    if (-not $InstallUpdates) { return }

    $steam = Find-ExistingPath -Candidates @(
        "${env:ProgramFiles(x86)}\Steam\steam.exe",
        "$env:ProgramFiles\Steam\steam.exe"
    )
    if (-not $steam) { return }

    # If Steam is already running, let it handle its own updates
    if (Test-ProcessRunning -ProcessName "steam") { return }

    # Launch Steam silently to trigger client + game updates
    $proc = Start-SilentProcess -FilePath $steam -Arguments @("-silent")
    if ($proc) { Start-Sleep -Seconds 30 }
}

# Epic Games Launcher
function Invoke-EpicUpdates {
    if (-not $InstallUpdates) { return }

    $epic = Find-ExistingPath -Candidates @(
        "${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe",
        "$env:ProgramFiles\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe",
        "$env:LocalAppData\EpicGamesLauncher\Portal\Binaries\Win64\EpicGamesLauncher.exe"
    )
    if (-not $epic) { return }

    # If Epic is already running, let it handle updates
    if (Test-ProcessRunning -ProcessName "EpicGamesLauncher") { return }

    # Launch Epic silently (it will check for self + game updates)
    $proc = Start-SilentProcess -FilePath $epic -Arguments @("-silent", "-background")
    if ($proc) { Start-Sleep -Seconds 30 }
}

# Other Gaming Launchers
function Invoke-OtherGameLaunchers {
    if (-not $InstallUpdates) { return }

    $launchers = @(
        @{
            Name = "EA App"
            Exe  = Find-ExistingPath -Candidates @(
                "$env:ProgramFiles\Electronic Arts\EA Desktop\EA Desktop\EA Desktop.exe",
                "$env:ProgramFiles\Electronic Arts\EA App\EA App.exe",
                "$env:LocalAppData\Electronic Arts\EA Desktop\EA Desktop.exe"
            )
            Args = @("-silent", "-background")
            ProcessName = "EADesktop"
        }
        @{
            Name = "Ubisoft Connect"
            Exe  = Find-ExistingPath -Candidates @(
                "$env:ProgramFiles\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe",
                "$env:ProgramFiles(x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe"
            )
            Args = @("--silent", "--background")
            ProcessName = "UbisoftConnect"
        }
        @{
            Name = "Battle.net"
            Exe  = Find-ExistingPath -Candidates @(
                "$env:ProgramFiles\Battle.net\Battle.net.exe",
                "$env:ProgramFiles(x86)\Battle.net\Battle.net.exe"
            )
            Args = @("--silent", "--background")
            ProcessName = "Battle.net"
        }
        @{
            Name = "Xbox"
            Exe  = Find-ExistingPath -Candidates @(
                "$env:ProgramFiles\WindowsApps\Microsoft.GamingApp_*\Xbox.exe",
                "$env:LocalAppData\Microsoft\WindowsApps\Xbox.exe"
            )
            Args = @()
            ProcessName = "Xbox"
        }
        @{
            Name = "Riot Client"
            Exe  = Find-ExistingPath -Candidates @(
                "$env:ProgramFiles\Riot Client\RiotClientServices.exe",
                "$env:LocalAppData\Riot Games\Riot Client\RiotClientServices.exe"
            )
            Args = @("--silent", "--background")
            ProcessName = "RiotClientServices"
        }
        @{
            Name = "Rockstar Games Launcher"
            Exe  = Find-ExistingPath -Candidates @(
                "$env:ProgramFiles\Rockstar Games\Launcher\RockstarGamesLauncher.exe",
                "$env:ProgramFiles(x86)\Rockstar Games\Launcher\RockstarGamesLauncher.exe"
            )
            Args = @("-silent")
            ProcessName = "RockstarGamesLauncher"
        }
        @{
            Name = "GOG Galaxy"
            Exe  = Find-ExistingPath -Candidates @(
                "$env:ProgramFiles\GOG Galaxy\GalaxyClient.exe",
                "$env:ProgramFiles(x86)\GOG Galaxy\GalaxyClient.exe"
            )
            Args = @("/silent", "/background")
            ProcessName = "GalaxyClient"
        }
    )

    foreach ($launcher in $launchers) {
        if (-not $launcher.Exe) { continue }
        if (Test-ProcessRunning -ProcessName $launcher.ProcessName) { continue }

        try {
            $proc = Start-SilentProcess -FilePath $launcher.Exe -Arguments $launcher.Args
            if ($proc) { Start-Sleep -Seconds 20 }
        } catch { }
    }
}

# Third-party applications via WinGet (already covered by Invoke-WingetUpdates)
# This function is a placeholder for future vendor-specific updaters
function Invoke-ThirdPartyUpdates {
    # WinGet already covers most third-party apps
    # Vendor-specific updaters (NVIDIA, Armoury Crate, Steam, Epic, etc.) are handled above
    return
}

# ─── Main Execution ─────────────────────────────────────────────────────────
try {
    # Order matters: OS first, then apps, then gaming
    Invoke-WindowsUpdate
    Invoke-WingetUpdates
    Invoke-MicrosoftStoreUpdates
    Invoke-NvidiaUpdates
    Invoke-ArmouryCrateUpdates
    Invoke-SteamUpdates
    Invoke-EpicUpdates
    Invoke-OtherGameLaunchers
    Invoke-ThirdPartyUpdates
}
finally {
    if ($hasUpdateMutex) { $updateMutex.ReleaseMutex() }
}