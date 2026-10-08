# Universal Silent Windows Update Automator

A PowerShell-based automation system that silently keeps Windows, drivers, applications, Microsoft Store packages, NVIDIA software, Armoury Crate, Steam, Epic Games, and other supported gaming launchers up to date once per day when Wi-Fi is connected.

The project is designed to run in the background with no reports or persistent logs, no forced Windows restart, and no unnecessary user interaction.

> **Important:** This project uses supported update mechanisms where possible. It does **not** claim that every Windows application or game can be silently updated. Software without a safe, supported unattended update mechanism is skipped gracefully.

## Features

- 🔄 Windows Update installation through `Microsoft.Update.Session`
- 📦 WinGet application upgrades
- 🏪 Microsoft Store updates through the WinGet `msstore` source
- 🎮 Steam background/client and game update support
- 🎮 Epic Games Launcher background update support
- 🖥️ Best-effort NVIDIA software update support
- 💻 Best-effort ASUS Armoury Crate support
- 🎮 Detection/support paths for EA App, Ubisoft Connect, Battle.net, Xbox, Riot Client, Rockstar Games Launcher and GOG Galaxy
- 📅 Daily scheduled execution (3 AM ± 4hr random delay)
- 📶 Wi-Fi-aware execution (only runs updates when connected)
- 🔒 Named mutex prevents concurrent runs
- 🤫 Hidden/background execution
- ⏱️ Timeout protection
- 🛡️ Does not terminate user applications or games
- 🔁 Safe to run repeatedly
- 🚫 Never intentionally restarts Windows
- 📝 No persistent reports or log files

## How It Works

```text
Daily trigger (3 AM ± 4hr random)
       │
       ▼
Task Scheduler
       │
       ▼
Hidden VBS launcher
       │
       ▼
PowerShell -WindowStyle Hidden
       │
       ▼
Acquire mutex
       │
       ▼
Verify Wi-Fi
       │
       ├── Windows Update
       ├── WinGet
       ├── Microsoft Store
       ├── NVIDIA
       ├── Armoury Crate
       ├── Steam
       ├── Epic Games
       └── Other supported launchers
       │
       ▼
Release mutex
       │
       ▼
Exit silently
```

Each provider is isolated. If one provider fails, the remaining providers can continue.

## Project Structure

```text
Universal-Silent-Windows-Update-Automator/
├── StartupUpdateCheck.ps1
├── Register-StartupUpdateCheck.ps1
├── RunStartupUpdateCheck.vbs
├── README.md
├── .gitignore
└── LICENSE
```

## Components

### `StartupUpdateCheck.ps1`

The main update engine.

It handles:

- Mutex acquisition
- Wi-Fi validation
- Windows Update
- WinGet
- Microsoft Store packages
- NVIDIA software
- Armoury Crate
- Steam
- Epic Games
- Other supported launchers
- Error isolation
- Process timeouts
- Mutex cleanup

Parameters:

```powershell
-RequireWifi
-InstallUpdates
```

### `Register-StartupUpdateCheck.ps1`

Creates the Windows Task Scheduler task:

**Codex Background Update Check**

The task is triggered by:

```text
Microsoft-Windows-NetworkProfile/Operational
Event ID 10000
```

The task runs using the current interactive user with least privilege.

### `RunStartupUpdateCheck.vbs`

A hidden launcher that starts PowerShell without displaying a console window.

## Update Providers

| Provider | Status | Mechanism |
|---|---|---|
| Windows Update | Full | `Microsoft.Update.Session` |
| WinGet | Full | `winget upgrade --all` |
| Microsoft Store | Full/conditional | WinGet `msstore` source |
| NVIDIA | Best-effort | NVIDIA App / installed vendor mechanism |
| Armoury Crate | Best-effort | ASUS installed mechanisms |
| Steam | Full/conditional | Steam client |
| Epic Games | Full/conditional | Epic Games Launcher |
| Other launchers | Best-effort | Installed launcher mechanisms |
| Third-party applications | Conditional | Primarily WinGet |

"Full" means the project has a practical supported mechanism. "Best-effort" means the vendor does not expose a universal documented unattended update interface, so the project detects and uses available mechanisms without claiming guaranteed updates.

## Supported Gaming Launchers

The project can detect common launchers such as:

- Steam
- Epic Games Launcher
- EA App
- Ubisoft Connect
- Battle.net
- Xbox / Microsoft Gaming
- Riot Client
- Rockstar Games Launcher
- GOG Galaxy

The updater does **not** blindly launch every possible game client. It first detects whether the software is installed and uses the least intrusive supported mechanism available.

## Safety and User Protection

The updater is designed not to interfere with active use.

It:

- Does not terminate user processes.
- Does not close running games.
- Does not force applications to close.
- Does not deliberately steal focus.
- Does not force Windows to restart.
- Does not modify vendor application databases.
- Does not download drivers from third-party websites.

If a relevant application is already running, the updater avoids starting a duplicate instance.

## Installation

Clone or download the repository, open PowerShell in the project directory, and run:

```powershell
.\Register-StartupUpdateCheck.ps1
```

Run it as the current user. Administrator elevation should not be required for the scheduled task configuration used by this project.

After registration, Windows will trigger the updater when the configured NetworkProfile event occurs.

## Manual Testing

### Check-only run

```powershell
.\StartupUpdateCheck.ps1
```

### Full update run

```powershell
.\StartupUpdateCheck.ps1 -RequireWifi -InstallUpdates
```

For testing, it is recommended to run the script manually first and verify that the expected update mechanisms behave correctly on the target system.

## Uninstall

Remove the scheduled task with:

```powershell
Unregister-ScheduledTask -TaskName "Codex Background Update Check" -Confirm:$false
```

The project files can then be deleted normally.

## Requirements

- Windows 10 version 1903 or later
- Windows 11
- PowerShell 5.1+
- Wi-Fi adapter for the Wi-Fi-triggered workflow
- WinGet / App Installer — recommended, but optional
- Relevant vendor software only when its update support is required

## Scheduled Task Configuration

| Setting | Value |
|---|---|
| Task name | `Codex Background Update Check` |
| Trigger | Daily at 3:00 AM (with 0-4 hour random delay) |
| User | Current interactive user |
| Privilege | Least privilege |
| Hidden | Yes |
| Network required | Yes |
| Execution time limit | 30 minutes |
| Action | `wscript.exe //B //NoLogo RunStartupUpdateCheck.vbs` |

## Concurrency Protection

The project uses the named mutex:

```text
CodexBackgroundUpdateCheck
```

This prevents multiple copies of the update engine from running simultaneously.

For example:

```text
Run A → Mutex acquired → continues

Run B → Mutex unavailable → exits silently
```

## Error Handling

Update providers are isolated from one another.

For example:

```text
Windows Update fails
        ↓
Continue to WinGet

WinGet fails
        ↓
Continue to NVIDIA

NVIDIA unavailable
        ↓
Continue to Steam

Steam unavailable
        ↓
Continue to Epic

...
```

A failure in one provider should not prevent other update mechanisms from being attempted.

## Timeouts

External update processes use timeout protection so that a stalled updater does not keep the entire process alive indefinitely.

The Task Scheduler registration also has a 30-minute execution limit.

## Security

This project intentionally avoids:

- Disabling Windows Defender
- Disabling SmartScreen
- Disabling UAC
- Modifying Windows security policies
- Downloading arbitrary scripts
- Executing unsigned third-party binaries
- Using unofficial driver repositories
- Modifying vendor application files/databases
- Hidden privilege escalation

The project prefers Microsoft- and vendor-provided update mechanisms.

## Limitations

### NVIDIA

NVIDIA does not provide a universal documented unattended command-line update interface for every installation. NVIDIA updates are therefore best-effort and depend on the installed NVIDIA application/mechanism.

### Armoury Crate

ASUS does not expose a universal documented silent update API for every Armoury Crate component. Support is therefore best-effort.

### Gaming Launchers

Gaming clients differ significantly in their command-line and background update capabilities. Some launchers may require their own UI or user session.

### Microsoft Store

Only Store applications exposed through a supported mechanism such as the WinGet `msstore` source can be handled automatically.

### Administrator-required updates

Some software and drivers require elevation. The project does not implement hidden privilege escalation. Such updates may be skipped.

### Reboot-required updates

Updates that require a reboot may be installed, but the project deliberately leaves the reboot to the user.

## What This Project Does Not Do

- ❌ Force Windows to restart
- ❌ Generate persistent reports or logs
- ❌ Guarantee updates for every application on Windows
- ❌ Guarantee updates for every installed game
- ❌ Download drivers from unofficial websites
- ❌ Bypass vendor security mechanisms
- ❌ Terminate running games or applications
- ❌ Modify vendor databases or installation files
- ❌ Silently elevate privileges without user authorization

## Design Philosophy

The project follows a simple rule:

> **Update everything that can be safely and legitimately updated through a supported mechanism, and gracefully skip everything else.**

There is no universal Windows API capable of silently updating every third-party application and game. A reliable updater therefore needs to combine several legitimate update mechanisms rather than pretending that one command can update everything.

## GitHub

Recommended repository name:

```text
Universal-Silent-Windows-Update-Automator
```

Suggested description:

```text
Silent PowerShell automation for Windows, application, driver, Microsoft Store, gaming launcher, and software updates.
```

## License

This project is intended to be released under the MIT License.

See `LICENSE` for the full license text.

## Disclaimer

Use this project at your own risk.

Software update behavior can change when Microsoft or third-party vendors change their installers, command-line interfaces, update services, or security policies. Always test the updater on your own system before relying on unattended updates.

---

**Built with PowerShell for automated Windows maintenance.**
