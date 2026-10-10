# Auto Hotspot

A single-file, self-healing Windows Mobile Hotspot. Double-click one file and the PC
becomes a locked-down Wi-Fi access point that stays on, with a fixed name, a fixed
password, room for 32 devices, and no idle auto-off.

Built for shared and lab machines, where the hotspot needs to be *there* every time a
student sits down, and where a standard user should not be able to quietly change it.

- **One file of real work.** `New-AutoHotspot.ps1` has no modules to install and no
  dependencies to fetch. Copy it and it runs.
- **One click.** `Run-Hotspot.cmd` handles the UAC prompt, unblocks the file, and works
  around the unsigned-script execution policy for you.
- **Self-healing.** A SYSTEM scheduled task re-runs it at boot, at logon, and every
  5 minutes. A hotspot that someone switched off is back within 5 minutes.
- **Fully reversible.** `Revert-Hotspot.cmd` puts the machine back exactly as Windows
  shipped it.

---

## Quick start

1. Download or clone this repo to the PC.
2. Double-click **`Run-Hotspot.cmd`**.
3. Click **Yes** on the User Account Control prompt.
4. Read the final report. Connect a phone or laptop to the hotspot.

The hotspot name is a random 32-character hex string (a UUID with the dashes removed),
and the password is always `12345678`. The report at the end prints the exact name.

> **Not on Windows?** This is a Windows-only tool. It calls the WinRT
> `NetworkOperatorTetheringManager` API through Windows PowerShell 5.1, which does not
> exist on PowerShell 7+ or on Windows 7/8.

---

## Before you start: read this bit

**Running `New-AutoHotspot.ps1` with no arguments reboots the computer after a
20-second countdown.** This is the script's own default behaviour, not a launcher
quirk — see the note under [Reboot behaviour](#reboot-behaviour) below.

`Run-Hotspot.cmd` passes `-NoReboot` for you, so double-clicking it is safe. If you
ever run the `.ps1` by hand, add `-NoReboot`, or be ready to save your work.

**Administrator rights are required.** The registry keys, the scheduled task, and the
Settings policy all live in `HKLM`, which only an elevated process can write. Without
elevation the script still starts the hotspot, but it cannot lock it down and prints a
warning instead.

**The hotspot is 5 GHz by default.** If nothing shows up in your phone's Wi-Fi list,
your adapter or the phone may not support 5 GHz. Re-run with `-Band 2.4GHz`.

---

## What it actually does

| Setting | Value | Where it is enforced |
| --- | --- | --- |
| Hotspot name | UUID without dashes, 32 hex chars | Reused across runs so devices stay joined |
| Password | `12345678`, always | Reset on every run; `-Password` cannot change it |
| Max clients | 32 | `HKLM\...\icssvc\Settings\WifiMaxPeers` |
| Idle auto-off | Disabled | `HKLM\...\icssvc\Settings\PeerlessTimeoutEnabled = 0` |
| Band | 5 GHz | Set on the access point configuration |
| Auto-start | Boot + logon + every 5 min | SYSTEM scheduled task `AutoHotspot-UUID` |
| UI lock | Hotspot detail page hidden | `HKLM\...\Policies\Explorer\SettingsPageVisibility` |

### The five-minute guard

The scheduled task re-runs this same script every 5 minutes, and each run first
compares the *live* hotspot configuration against the policy. If the name, password,
band, and on/off state all already match, **it does nothing** — it deliberately does
not restart tethering, because restarting would disconnect every connected device.
Only real drift or an off state triggers a reconfigure and restart.

That is why the password stays at `12345678` even if someone edits it in the UI, and
why the hotspot comes back if someone toggles it off.

### The name is a UUID on purpose

Wi-Fi Direct caps the SSID at 32 characters. A GUID formatted the normal way
(`3f2504e0-4f45-4446-8a7f-b72a7c4f1d2e`) is 36 characters and Windows silently
truncates it, which produces two confusing problems: the name you typed is not the
name that broadcasts, and the truncation can make the name unstable. Dropping the
dashes gives exactly 32 characters, so nothing is lost.

On the first run the script mints a new UUID. Every later run detects the existing
32-hex-character SSID and reuses it, so devices do not have to rejoin. Pass `-Ssid` to
pin your own name instead.

---

## Usage

### From the launchers

```
Run-Hotspot.cmd                    full setup, then start
Run-Hotspot.cmd -Show              report current state, change nothing
Run-Hotspot.cmd -Ssid MyLabWiFi    use a custom name
Run-Hotspot.cmd -Band 2.4GHz       2.4 GHz instead of 5 GHz
Run-Hotspot.cmd -Stop              stop the hotspot and exit
Run-Hotspot.cmd -Reboot            same, but reboot afterwards (opt-in)

Revert-Hotspot.cmd                 undo everything
```

The launcher suppresses the automatic reboot unless you ask for it by name. Passing
`-Reboot` makes it drop `-NoReboot` for that run, since the script refuses to accept
both switches at once.

### From PowerShell

```powershell
# Full workflow
.\New-AutoHotspot.ps1 -NoReboot

# Show current configuration without changing anything
.\New-AutoHotspot.ps1 -Show

# Fixed name and band
.\New-AutoHotspot.ps1 -Ssid "CampusLab" -Band 2.4GHz -NoReboot

# Configure but do not start
.\New-AutoHotspot.ps1 -Ssid "CampusLab" -NoStart

# Preview every change without applying any of them
.\New-AutoHotspot.ps1 -WhatIf

# Undo everything
.\New-AutoHotspot.ps1 -Revert

# Built-in help
.\New-AutoHotspot.ps1 -Help
Get-Help .\New-AutoHotspot.ps1 -Full
```

### All parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `-Ssid` | auto UUID | Hotspot name. Pin it to stop clients re-joining after a run. |
| `-Password` | `12345678` | Kept for compatibility. The value is always forced back to `12345678`. |
| `-Band` | `5GHz` | `Auto`, `2.4GHz`, `5GHz`, or `6GHz`. |
| `-Show` | off | Print state, SSID, band, auth, and client count. Changes nothing. |
| `-Stop` | off | Stop the hotspot and exit. |
| `-NoStart` | off | Configure only; do not start tethering. |
| `-NoAutoTask` | off | Skip installing the scheduled task and the lock. |
| `-InstallAutoTask` | off | Kept for compatibility; behaves like a normal run. |
| `-NoReboot` | off | Suppress the automatic reboot. **Recommended for manual runs.** |
| `-Reboot` | off | Reboot when finished, with a 20-second countdown. |
| `-RebootDelaySeconds` | `20` | Countdown length, 5 to 120 seconds. |
| `-LockPassword` | on | Hide the Settings page and install SYSTEM enforcement. |
| `-UnlockPassword` | off | Undo the lock. |
| `-Revert` | off | Full undo to Windows defaults. |
| `-Help` | off | Print help and exit. |
| `-WhatIf` | — | Built into PowerShell. Preview without changing anything. |

---

## Reboot behaviour

This is the single most surprising thing about the script, so it is worth stating
plainly:

> **A bare `.\New-AutoHotspot.ps1` reboots the computer.** Press `Ctrl+C` during the
> 20-second countdown to cancel it.

The default run is treated as a full workflow run, and a full workflow run ends with a
reboot so you can watch the auto-start task bring the hotspot back on a cold boot. The
help text lists `-Reboot` as though it were optional; the code makes it the default.

Two ways to avoid it:

- Use `Run-Hotspot.cmd`, which passes `-NoReboot` unless you explicitly ask it not to.
- Run the script with `-NoReboot` yourself.

`-Reboot` and `-NoReboot` together are rejected by the script, so the launcher treats an
explicit `-Reboot` as "you know what you are doing" and stops injecting `-NoReboot`.

The scheduled task is never affected — it always passes `-NoAutoTask -NoReboot`, so the
5-minute guard will never reboot a machine out from under a user.

---

## What "locked down" means, precisely

Be clear-eyed about this before deploying it on a machine other people use:

- **The Mobile Hotspot detail page is hidden in Settings** via the
  `SettingsPageVisibility` policy. Standard users cannot get to it to change the
  password. An administrator can still find it, and can bring it back with `-Revert`.
- **The enforcement task runs as SYSTEM**, not as the user who installed it. Standard
  users cannot disable or delete a SYSTEM-owned scheduled task from Task Scheduler.
  Deleting it requires an elevated prompt.
- **The hotspot name and password are shared constants**, not secrets. Anyone who can
  see the name can connect with `12345678`. This is appropriate for an open lab or
  classroom network and inappropriate anywhere else. If you need a real credential,
  do not use this script as-is.

On the hiding specifically: Windows exposes no policy that removes the "Mobile hotspot"
row from the Network & internet list. What gets hidden is the *detail page* behind that
row. The row stays visible and shows the restriction notice when opened. The Quick
Settings tile is likewise untouched.

If you want the lock removed without a full revert:

```powershell
.\New-AutoHotspot.ps1 -UnlockPassword -NoReboot
```

---

## Reverting

```powershell
.\New-AutoHotspot.ps1 -Revert -NoReboot
```

or double-click `Revert-Hotspot.cmd`. This:

1. Deletes `WifiMaxPeers`, putting the client limit back to the Windows default of 8.
2. Deletes `PeerlessTimeoutEnabled`, turning the idle auto-off back on.
3. Un-hides the Mobile Hotspot Settings page.
4. Deletes the `AutoHotspot-UUID` scheduled task.
5. Resets the hotspot name to the PC name with a fresh random password on Auto band,
   and leaves the hotspot **off**.

The new random password is printed at the end — save it if you intend to turn the
hotspot back on from Settings.

---

## Requirements

- Windows 10 or 11.
- Windows PowerShell 5.1 (the one that ships with Windows). Not PowerShell 7+.
- An active internet connection at run time, over Wi-Fi or Ethernet. The hotspot shares
  the PC's connection, so there has to be something to share.
- A wireless adapter that supports Mobile Hotspot / Wi-Fi Direct.
- Administrator rights for the locking features.

---

## Troubleshooting

**Nothing appears in the phone's Wi-Fi list.**
Almost always a band mismatch. Try `-Band 2.4GHz`, or `-Band Auto` to let the adapter
choose.

**`StartTetheringAsync` fails.**
The script needs a working internet connection profile, and it polls for up to 3 minutes
for one to appear. It throws `No active internet connection profile found after 3 min`
if it never shows up. Check that the PC itself is online — a hotspot with nothing
upstream is not much use.

**The script will not run at all.**
Windows PowerShell 5.1 blocks downloaded `.ps1` files two ways: the Mark-of-the-Web,
and the execution policy. Use `Run-Hotspot.cmd`, which handles both. To fix it by hand:

```powershell
Unblock-File .\New-AutoHotspot.ps1
powershell -ExecutionPolicy Bypass -File .\New-AutoHotspot.ps1 -NoReboot
```

If you would rather relax the policy for the current user only:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Do **not** set `ExecutionPolicy Unrestricted` machine-wide. The launchers use
`-ExecutionPolicy Bypass`, which applies to that one process and changes nothing
persistent.

**It says it could not enforce the 32-client limit, or could not hide the Settings page.**
You are not elevated. Close the window, right-click `Run-Hotspot.cmd`, and choose
**Run as administrator**.

**The hotspot keeps getting kicked.**
Something is resetting it. Check the run log at
`%ProgramData%\AutoHotspot\run.log` — every headless task run appends to it.

**The 5 GHz band will not set.**
Some adapters refuse 5 GHz for tethering even when they support it for normal Wi-Fi.
The script warns and keeps the adapter default rather than failing outright. Use
`-Band Auto` on those machines.

**The task name is not `AutoHotspot-UUID`.**
It always is. If `Lock-HotspotPassword` reports that the task is still running as a
user instead of SYSTEM, an older user-scoped task survived the replace. Delete
`\AutoHotspot-UUID` from Task Scheduler manually and re-run.

---

## Run log

Headless runs — the boot, logon, and 5-minute guard runs — write to:

```
%ProgramData%\AutoHotspot\run.log
```

This is the first place to look when the hotspot is not coming back on its own and
nobody is sitting at the machine to see an error.

---

## Files

```
New-AutoHotspot.ps1    The whole tool. Single file, no dependencies.
Run-Hotspot.cmd        One-click launcher: UAC + unblock + execution-policy bypass.
Revert-Hotspot.cmd     One-click full undo.
```

---

## Notes on the implementation

A few decisions worth knowing if you plan to modify the script:

- **It uses `NetworkOperatorTetheringManager`, not `netsh wlan set hostednetwork`.**
  The legacy `netsh` hostednetwork mode is not supported by modern adapters, including
  the Qualcomm FastConnect 7800. The WinRT tethering API is the supported path on
  Windows 10 and 11. Do not "simplify" this back to `netsh`.
- **Async WinRT calls are awaited by hand.** PowerShell 5.1 cannot call `.GetResults()`
  on a `ComObject`, so `Await-Action` and `Await-Op` bridge the WinRT async operations
  to .NET tasks through `System.WindowsRuntimeSystemExtensions.AsTask`.
- **The connection profile is polled for up to 3 minutes** at startup. At boot the
  Wi-Fi or Ethernet profile can take a minute or more to appear, and without this the
  boot trigger fails on its first attempt.
- **`icssvc` is only restarted when a value actually changed.** Restarting it
  unconditionally would flap the hotspot and drop connected clients on every guard run.

---

## License

MIT. Use it, adapt it, take it apart.
