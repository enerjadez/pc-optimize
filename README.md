# Windows Optimize

Portable Windows 10 / 11 performance pack. Copy the folder onto a PC, run **`APPLY.bat`**, reboot.

It **detects what is on that machine**. Missing Armoury Crate or iCUE? Those lines are skipped. It will not disable Defender, Firewall, Windows Update, audio, Wi-Fi, Office Click-to-Run, GPU crash services, or anti-cheat.

## On a new PC

1. Copy this whole folder (USB, zip, whatever). Keep the files together.
2. Optional: **`PREVIEW.bat`** — shows the plan, writes nothing.
3. **`APPLY.bat`** — Yes on UAC, then **Y**.
4. Reboot once.

Undo on **that same PC**: **`RESTORE.bat`**.

| File | What it does |
|---|---|
| `PREVIEW.bat` | Plan only. |
| `APPLY.bat` | Apply. Asks Y/N. |
| `RESTORE.bat` | Last backup on this PC. |
| `AUDIT.bat` | Inventory services + startup keys. |

```powershell
.\Optimize.ps1 -Action Preview
.\Optimize.ps1 -Action Apply -Yes
.\Optimize.ps1 -Action Restore
.\Optimize.ps1 -Action Audit
```

| Switch | Meaning |
|---|---|
| `-KeepLaunchers` | Leave Steam / Epic / Riot / Battle.net / EA / Ubisoft in startup |
| `-KeepPrinter` | Leave Print Spooler |
| `-KeepWSL` | Leave WSL |
| `-KeepSearch` | Leave Windows Search indexing |
| `-KeepXbox` | Leave Xbox Live services |
| `-KeepPhone` | Leave Phone Link |
| `-NoHags` | Do not turn on hardware-accelerated GPU scheduling |
| `-Yes` | Skip Y/N |
| `-NoRestorePoint` | Skip the Windows restore-point attempt |

## What it does

**Services → Manual** (Disabled only for Killer / SmartByte, which sit on the NIC):

OEM RGB suites, launcher updaters, telemetry (`DiagTrack`), Superfetch, Search indexer, Delivery Optimization, Xbox Live, Print Spooler, WSL, Phone Link, maps, fax, retail demo, and other idle Windows extras. They start again if an app asks.

**Startup cleared:** game launchers, RGB trays, Docker, Chrome/Edge silent launch, Discord, Spotify, OneDrive, Teams, GeForce Experience overlay, plus Startup-folder shortcuts (renamed `.bak`).

**Scheduled tasks disabled (not deleted):** Compatibility Appraiser, CEIP, Disk Diagnostic collector, Maps, Xbox save, Office telemetry, Google/Adobe/CCleaner/Overwolf updaters, power-efficiency diagnostics.

**Latency / desktop:**

- Game Mode on, Game DVR / overlay off
- Hardware-accelerated GPU scheduling on
- Pointer precision off, animations off, menu delay 0
- Fast Startup off, UWP background apps off
- Widgets / Copilot / News and interests / Recall off
- Telemetry **basic** (not 0 — 0 breaks pieces of Windows 11)
- Prefetch / Superfetch off, NTFS last-access off
- Games MMCSS High, network throttle off, Nagle off
- **Desktop:** Ultimate Performance, hibernate off
- **Laptop:** High Performance (Ultimate would drain the battery)
- On AC: CPU 100%, core parking off, USB / PCIe / disk idle off

**Never touched:** Defender, Firewall, Windows Update, BITS, audio stack, core RPC/PnP, Gaming Services, anti-cheat (Vanguard / EAC / BattlEye / FACEIT), AMD crash/events, NVIDIA display container, Office Click-to-Run, fingerprint on laptops.

## Backups

Every Apply writes:

```
%ProgramData%\WinOptimize\backup-YYYYMMDD-HHMMSS-PCNAME.json
```

Restore reads the latest one **on that PC**. Each machine keeps its own.

## After apply

| Want | Do this |
|---|---|
| Steam / Epic / games | Open the app |
| RGB | Open iCUE / Armoury / MSI Center |
| Docker / WSL | Open it |
| Print | `Start-Service Spooler` |
| Start-menu search feel slow | `.\Optimize.ps1 -Action Apply -KeepSearch -Yes` then reboot |
| Valorant | Vanguard often re-adds its tray itself |

Windows 11 will not drop to 20 running services. Lean and healthy is roughly 90–110. Going lower usually breaks Store, audio, or updates.

This is not a GPU driver, not a game-settings preset, and not an anti-cheat bypass.
