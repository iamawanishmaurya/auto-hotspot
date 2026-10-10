<#
.SYNOPSIS
    Self-healing, locked-down Windows Mobile Hotspot. No arguments = full workflow.

.DESCRIPTION
    WHAT WE ARE BUILDING
    --------------------
    A portable, standalone (single-file, no dependencies) hotspot manager that
    turns this PC into an always-on access point with fixed policy:
      * SSID     : UUID without dashes (32 hex chars = SSID max length).
                   First run generates it; later runs REUSE it so clients stay
                   joined. Pass -Ssid to pin a custom name.
      * Password : ALWAYS 12345678. Every run resets any manual change.
      * Clients  : 32, via HKLM...\icssvc\Settings WifiMaxPeers (needs Admin).
      * Idle     : never auto-offs — PeerlessTimeoutEnabled=0 in the same key
                   (needs Admin, icssvc restarted once to apply).
      * Band     : 5GHz (pass -Band Auto on 2.4GHz-only adapters).
      * Healing  : a SYSTEM Scheduled Task (boot + logon + every 5 min)
                   re-runs this script, so a hotspot someone turned OFF or
                   reconfigured is back within 5 minutes.
      * Lock     : the Mobile Hotspot *detail* Settings page is hidden by
                   policy, so standard users cannot change it in the UI.
                   Reverting needs Admin (-UnlockPassword).

    HOW IT WORKS (pipeline, in order)
    ---------------------------------
      1. Resolve SSID   : reuse live SSID, else mint a fresh UUID.
      2. Enforce policy : force password 12345678, write WifiMaxPeers=32.
      3. Guard check    : compare live SSID/pass/band/state. If all match and
                          state is On, do NOTHING (avoids kicking clients).
                          If OFF or drifted, reconfigure + restart tethering
                          via NetworkOperatorTetheringManager (modern Wi-Fi
                          Direct API; netsh hostednetwork does NOT work on
                          cards like Qualcomm FastConnect 7800).
      4. Persist        : (re)install AutoHotspot-UUID task + hide Settings page.
      5. Report         : print State/Ssid/Band/Auth/Clients + lock flags.
                          Optional -Reboot reboots to prove auto-start on boot.

    REQUIREMENTS
    ------------
      * Windows 10/11 + Windows PowerShell 5.1 (WinRT API; not PS 7, not Win7/8).
      * Active internet connection (Wi-Fi/Ethernet) at run time.
      * Admin ONCE for WifiMaxPeers + task + Settings policy. Later
        config/start runs work as standard user (with warnings for Admin steps).

    AUTO-SET DIAGRAM (no-arg run)
    -----------------------------
      .\New-AutoHotspot.ps1
      │
      ├─ 1. SSID ......... live SSID exists? REUSE it : mint fresh UUID(N)
      ├─ 2. Password ..... force 12345678 (resets any manual change)
      ├─ 3. Clients ...... WifiMaxPeers = 32 ............ [Admin, HKLM]
      ├─ 4. Idle ......... PeerlessTimeoutEnabled = 0 ... [Admin, HKLM]
      │                    (+ restart icssvc ONLY if the value changed)
      ├─ 5. Guard ........ compare live SSID/pass/band/state
      │   ├─ all match + ON ... do NOTHING (clients stay joined)
      │   └─ OFF or drift ..... ConfigureAccessPointAsync + StartTetheringAsync
      │                         (Band = 5GHz, Auth stays Wpa3TransitionMode)
      ├─ 6. Lock ......... hide Settings detail page ...... [Admin, policy]
      │                    SYSTEM task: boot + logon + every 5 min
      │                    (non-admins cannot disable it; each run re-enforces
      │                    steps 2-5, so OFF/changes revert within 5 min)
      └─ 7. Report ....... State/Ssid/Band/Auth/Clients + lock flags
                           (-Reboot optional: 20s countdown, proves boot start)

      REVERT (.\New-AutoHotspot.ps1 -Revert, needs Admin)
      │  deletes WifiMaxPeers (=8 again) + PeerlessTimeoutEnabled
      │  (idle-off back on), unhides Settings page, deletes the task,
      │  resets name to PC name + random password on Auto, hotspot OFF.

      Persisted where: HKLM\...\icssvc\Settings (WifiMaxPeers,
        PeerlessTimeoutEnabled), Task Scheduler \AutoHotspot-UUID,
        HKLM\...\Policies\Explorer SettingsPageVisibility.

    NOTE ON HIDING (see screenshot question)
    ----------------------------------------
      hide:network-mobilehotspot hides the hotspot DETAIL page, not the
      "Mobile hotspot" ROW on the Network & internet list. The row stays
      visible; opening it shows the restriction notice. Windows offers no
      policy to remove the row itself.

    Password must be 8-63 ASCII chars. Fixed to 12345678 per request.

.PARAMETER Ssid
    Hotspot name. Defaults to a fresh UUID without dashes, e.g.
    3f2504e04f4544468a7fb72a7c4f1d2e. Pass -Ssid to pin a fixed name so
    clients do not have to rejoin after every run.

.PARAMETER Password
    Always enforced to 12345678. Parameter kept for override, but default
    run resets any manual change back to 12345678.

.PARAMETER Band
    Auto, 2.4GHz, 5GHz or 6GHz. Defaults to 5GHz per request.

.PARAMETER Show
    Show current hotspot config and state. Changes nothing.

.PARAMETER Stop
    Stop the hotspot and exit. Changes nothing else.

.PARAMETER NoStart
    Only configure SSID/password, do not start the hotspot.

.PARAMETER InstallAutoTask
    Kept for compatibility. Auto-task is now installed on every normal run
    unless -NoAutoTask is given.

.PARAMETER NoAutoTask
    Skip installing the logon+startup Scheduled Task.

.PARAMETER Reboot
    Auto-reboot when finished (20s countdown, Ctrl+C aborts). Used to verify
    the auto-start task brings the hotspot back on boot.

.PARAMETER RebootDelaySeconds
    Countdown before reboot. Defaults to 20.

.PARAMETER LockPassword
    Now the default on every normal run. Flag kept so
    .\New-AutoHotspot.ps1 -LockPassword still works explicitly.

.PARAMETER UnlockPassword
    Remove the -LockPassword hardening (show Settings page again, task back
    to user logon+startup).

.PARAMETER Revert
    Undo EVERYTHING back to Windows defaults: delete WifiMaxPeers (limit
    back to 8), delete PeerlessTimeoutEnabled (idle auto-off back on),
    unhide the Settings hotspot page, delete the AutoHotspot-UUID task,
    reset hotspot name to this PC name with a fresh random password on
    Auto band, and leave the hotspot OFF. Needs Admin for registry/task.

.PARAMETER Help
    Show the help menu and exit. Changes nothing.

.EXAMPLE
    .\New-AutoHotspot.ps1 -Show
    .\New-AutoHotspot.ps1
    .\New-AutoHotspot.ps1 -Ssid my-fixed-name
    .\New-AutoHotspot.ps1 -Ssid "8c7eb87235a74041b6181d8075446eeb" -Band 5GHz -Reboot
    .\New-AutoHotspot.ps1 -LockPassword
    .\New-AutoHotspot.ps1 -Revert
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Ssid = '',
    [string]$Password = '12345678',
    [ValidateSet('Auto', '2.4GHz', '5GHz', '6GHz')]
    [string]$Band = '5GHz',
    [switch]$Show,
    [switch]$Stop,
    [switch]$NoStart,
    [switch]$InstallAutoTask,
    [switch]$NoAutoTask,
    [switch]$Reboot,
    [switch]$NoReboot,
    [ValidateRange(5, 120)]
    [int]$RebootDelaySeconds = 20,
    [switch]$LockPassword,
    [switch]$UnlockPassword,
    [switch]$Revert,
    [switch]$Help
)

function Invoke-RebootCountdown($Seconds) {
    Write-Host ''
    Write-Host ("Rebooting in {0}s. Save work. Ctrl+C aborts." -f $Seconds) -ForegroundColor Yellow
    for ($i = $Seconds; $i -gt 0; $i--) {
        Write-Host ("  {0,3}s ..." -f $i) -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ''
    Restart-Computer -Force
}

function Get-TetheringManager {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null
    $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
    $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
    $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]

    # Boot retry: at startup the Wi-Fi/Ethernet profile may take 1-3 min to appear.
    # Poll for up to ~3 min so the boot/logon task does not fail on first try.
    $profile = $null
    for ($i = 0; $i -lt 18; $i++) {
        $profile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
        if ($profile) { break }
        Start-Sleep -Seconds 10
    }
    if (-not $profile) { throw 'No active internet connection profile found after 3 min. Connect to Wi-Fi/Ethernet first.' }
    return [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)
}

function Write-RunLog([string]$Message) {
    # Task runs are headless; log to ProgramData so boot failures are visible.
    try {
        $dir = Join-Path $env:ProgramData 'AutoHotspot'
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Add-Content -Path (Join-Path $dir 'run.log') -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -ErrorAction Stop
    } catch { }
}

function Await-Action($op) {
    # IAsyncAction -> .NET Task and wait (PowerShell 5.1 has no .GetResults on ComObject)
    $m = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and -not $_.IsGenericMethod
    })[0]
    $task = $m.Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
}

function Await-Op($op, $resultType) {
    # IAsyncOperation<T> -> .NET Task<T> and wait, returns T
    $generic = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]
    $task = $generic.MakeGenericMethod($resultType).Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    return $task.Result
}

function Ensure-ClientLimit32 {
    # Enforces WifiMaxPeers=32 so MaxClientCount stays 32 across reboots.
    # Needs Admin for HKLM write; warns instead of failing when not elevated.
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\icssvc\Settings'
    try {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $key -Name 'WifiMaxPeers' -PropertyType DWord -Value 32 -Force -ErrorAction Stop | Out-Null
        try { Set-Service -Name 'icssvc' -StartupType Automatic -ErrorAction Stop } catch { }
        Write-Host '  client limit enforced: 32 (WifiMaxPeers)'
        return $true
    }
    catch {
        Write-Warning ("Could not enforce 32-client limit (need Admin): {0}" -f $_.Exception.Message)
        return $false
    }
}

function Ensure-AutoTask($TaskSsid, $TaskPassword, $TaskBand, $ScriptPath) {
    $taskName = 'AutoHotspot-UUID'
    $taskArgs = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Ssid "{1}" -Band {2} -NoAutoTask -NoReboot' -f $ScriptPath, $TaskSsid, $TaskBand)
    # Password is intentionally omitted: script always enforces 12345678.
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs -ErrorAction Stop
    $triggers = @(
        (New-ScheduledTaskTrigger -AtLogOn),
        (New-ScheduledTaskTrigger -AtStartup)
    )
    # 1-min delay lets the network stack come up before tethering starts.
    foreach ($t in $triggers) { $t.Delay = 'PT30S' }
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -ErrorAction Stop
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ErrorAction Stop
    Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $triggers -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    Write-Host ("  auto-start task '{0}' installed (logon + startup, 1min delay)." -f $taskName)
}

function Ensure-IdleAlwaysOn {
    # Disables the ~5-min idle auto-off ("power saving") via PeerlessTimeoutEnabled=0.
    # icssvc must be restarted for it to take effect; restart only when a value
    # actually changed so steady-state runs do not flap the hotspot.
    # Needs Admin for HKLM write + service restart.
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\icssvc\Settings'
    try {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
        $cur = (Get-ItemProperty -Path $key -Name 'PeerlessTimeoutEnabled' -ErrorAction SilentlyContinue).PeerlessTimeoutEnabled
        if ($cur -eq 0) {
            Write-Host '  idle auto-off already disabled (PeerlessTimeoutEnabled=0)'
            return $true
        }
        New-ItemProperty -Path $key -Name 'PeerlessTimeoutEnabled' -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
        Write-Host '  idle auto-off disabled (PeerlessTimeoutEnabled=0), restarting icssvc...'
        Restart-Service -Name 'icssvc' -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning ("Could not disable idle auto-off (need Admin): {0}" -f $_.Exception.Message)
        return $false
    }
}

function Get-BandValue([string]$Name) {
    # TetheringWiFiBand: Auto=0, 2.4GHz=1, 5GHz=2, 6GHz=3
    switch ($Name) {
        '2.4GHz' { return 1 }
        '5GHz'   { return 2 }
        '6GHz'   { return 3 }
        default  { return 0 }
    }
}

function Test-IsSystemPrincipal($UserId) {
    # Compatible across Windows builds: same SYSTEM account reports as
    # 'S-1-5-18', 'SYSTEM', or 'NT AUTHORITY\SYSTEM' depending on version.
    return ($UserId -eq 'S-1-5-18' -or $UserId -ieq 'SYSTEM' -or $UserId -ieq 'NT AUTHORITY\SYSTEM')
}

function Get-LockState {
    $pol = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue).SettingsPageVisibility
    $hidden = ($null -ne $pol -and $pol -like '*network-mobilehotspot*')
    $task = Get-ScheduledTask -TaskName 'AutoHotspot-UUID' -ErrorAction SilentlyContinue
    $asSystem = ($null -ne $task -and (Test-IsSystemPrincipal $task.Principal.UserId))
    [pscustomobject]@{ SettingsHidden = $hidden; EnforcedBySystem = $asSystem }
}

function Lock-HotspotPassword($ScriptPath, $TaskSsid, $TaskBand) {
    # 1. Hide Mobile Hotspot page in Settings (needs Admin to revert).
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
    $cur = (Get-ItemProperty -Path $key -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue).SettingsPageVisibility
    if ([string]::IsNullOrWhiteSpace($cur)) { $new = 'hide:network-mobilehotspot' }
    elseif ($cur -like '*network-mobilehotspot*') { $new = $cur }
    elseif ($cur -like 'hide:*') { $new = $cur + ';network-mobilehotspot' }
    else { $new = $cur + ';hide:network-mobilehotspot' }
    New-ItemProperty -Path $key -Name 'SettingsPageVisibility' -PropertyType String -Value $new -Force -ErrorAction Stop | Out-Null
    Write-Host '  Settings page hidden: network-mobilehotspot (Admin can revert with -UnlockPassword)'

    # 2. SYSTEM task every 5 min + boot/logon: reverts any password change fast
    #    and restarts the hotspot if someone turned it off.
    #    Non-admins cannot disable/delete SYSTEM tasks.
    $taskArgs = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Ssid "{1}" -Band {2} -NoAutoTask -NoReboot' -f $ScriptPath, $TaskSsid, $TaskBand)
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs -ErrorAction Stop
    $triggers = @(
        (New-ScheduledTaskTrigger -AtStartup),
        (New-ScheduledTaskTrigger -AtLogOn)
    )
    foreach ($t in $triggers) { $t.Delay = 'PT30S' }
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650) -ErrorAction Stop
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest -ErrorAction Stop
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ErrorAction Stop
    Register-ScheduledTask -TaskName 'AutoHotspot-UUID' -Action $act -Trigger @($triggers + $repeat) -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    # Verify replace: the old user-level task must actually be gone, not merged.
    $check = Get-ScheduledTask -TaskName 'AutoHotspot-UUID' -ErrorAction Stop
    if (-not (Test-IsSystemPrincipal $check.Principal.UserId)) {
        throw ("Task still runs as '{0}', expected SYSTEM. Delete '\AutoHotspot-UUID' manually and re-run." -f $check.Principal.UserId)
    }
    Write-Host '  enforcement task now SYSTEM every 5 min + boot/logon.'
}

function Unlock-HotspotPassword($ScriptPath, $TaskSsid, $TaskBand) {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $cur = (Get-ItemProperty -Path $key -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue).SettingsPageVisibility
    if ($null -ne $cur -and $cur -like '*network-mobilehotspot*') {
        $new = ($cur -split ';' | Where-Object { $_ -ne 'network-mobilehotspot' -and $_ -ne 'hide:network-mobilehotspot' -and $_ -ne 'hide' }) -join ';'
        if ([string]::IsNullOrWhiteSpace($new)) { Remove-ItemProperty -Path $key -Name 'SettingsPageVisibility' -Force -ErrorAction Stop }
        else { New-ItemProperty -Path $key -Name 'SettingsPageVisibility' -PropertyType String -Value $new -Force -ErrorAction Stop | Out-Null }
        Write-Host '  Settings page unhidden.'
    }
    else { Write-Host '  Settings page was not hidden.' }
    Ensure-AutoTask -TaskSsid $TaskSsid -TaskPassword '12345678' -TaskBand $TaskBand -ScriptPath $ScriptPath
}

function Show-Current($Manager) {
    $cur = $Manager.GetCurrentAccessPointConfiguration()
    [pscustomobject]@{
        State    = $Manager.TetheringOperationalState.ToString()
        Ssid     = $cur.Ssid
        Band     = $cur.Band.ToString()
        Auth     = $cur.AuthenticationKind.ToString()
        Clients  = ('{0}/{1}' -f $Manager.ClientCount, $Manager.MaxClientCount)
    } | Format-List | Out-String | Write-Host
    $lock = Get-LockState
    Write-Host ("Lock     : settings-hidden={0}, system-enforced={1}" -f $lock.SettingsHidden, $lock.EnforcedBySystem)
}

# --- always enforce fixed password -----------------------------------------
if ($Password -ne '12345678') {
    Write-Host '  password overridden back to 12345678 (fixed policy).'
    $Password = '12345678'
}

if ($Help) {
    Write-Host @'

  New-AutoHotspot.ps1 - self-healing, locked-down Mobile Hotspot (standalone)
  ==========================================================================
  No arguments = full workflow: enforce 12345678 / 32 clients / 5GHz /
  always-on, start hotspot, install boot+logon+5min SYSTEM task, hide
  the Settings hotspot detail page.

  USAGE
    .\New-AutoHotspot.ps1 [-Ssid NAME] [-Band Auto|2.4GHz|5GHz|6GHz] [switches]

  SWITCHES
    -Show ............ current State/Ssid/Band/Auth/Clients + lock flags
    -Help ............ this menu (changes nothing)
    -Stop ............ stop the hotspot, exit
    -NoStart ......... configure only, do not start
    -NoAutoTask ...... skip task install / lock hardening
    -InstallAutoTask . same as default run (kept for compatibility)
    -LockPassword .... hide Settings page + SYSTEM task (default every run)
    -UnlockPassword .. unhide Settings page, task back to user level
    -Revert .......... full undo to Windows defaults (limit 8, idle-off on,
                       Settings shown, task deleted, PC-name + random pass)
    -Reboot .......... reboot when done (20s countdown, Ctrl+C aborts)
    -WhatIf .......... preview without changing anything

  EXAMPLES
    .\New-AutoHotspot.ps1 -Help
    .\New-AutoHotspot.ps1 -Show
    .\New-AutoHotspot.ps1
    .\New-AutoHotspot.ps1 -Ssid "MyHotspot" -Band Auto
    .\New-AutoHotspot.ps1 -Revert
    Get-Help .\New-AutoHotspot.ps1 -Full   # complete documentation

  NOTES
    * First run needs Admin (registry + task + Settings policy).
    * Needs Windows 10/11 + PowerShell 5.1 with active internet.
    * Quick Settings tile + Settings list row always stay visible;
      only the hotspot detail page is hidden by the lock.

'@
    return
}

$manager = $null
try { $manager = Get-TetheringManager }
catch {
    Write-RunLog ("FAIL no-internet-profile: {0}" -f $_.Exception.Message)
    throw
}
Write-RunLog ("run start ssid-param='{0}' band={1} args-NoAutoTask={2}" -f $Ssid, $Band, $NoAutoTask.IsPresent)

# --- resolve SSID: default to UUID, keep UUID stable -------------------------
# No -Ssid given -> if live SSID is already UUID(N), reuse it unchanged.
# Otherwise (ASUS, PC name, empty, anything non-UUID) mint a fresh UUID.
# After first migration, later runs see UUID and keep it constant.
if ([string]::IsNullOrWhiteSpace($Ssid) -and -not $Show -and -not $Stop) {
    try { $existing = $manager.GetCurrentAccessPointConfiguration().Ssid } catch { $existing = '' }
    if (-not [string]::IsNullOrWhiteSpace($existing) -and $existing -match '^[0-9a-fA-F]{32}$') {
        $Ssid = $existing
        Write-Host ("  reusing existing UUID SSID: {0}" -f $Ssid)
    }
    else {
        # UUID without dashes = 32 hex chars, exactly the SSID max length.
        $Ssid = [guid]::NewGuid().ToString('N')
        if ([string]::IsNullOrWhiteSpace($existing)) { Write-Host ("  fresh UUID SSID: {0}" -f $Ssid) }
        else { Write-Host ("  migrating SSID '{0}' -> UUID '{1}'" -f $existing, $Ssid) }
    }
}

if ($Show) {
    Show-Current $manager
    return
}

if ($Stop) {
    if ($PSCmdlet.ShouldProcess('Mobile Hotspot', 'Stop')) {
        Await-Action ($manager.StopTetheringAsync())
        Write-Host 'Hotspot stopped.'
    }
    return
}

if ($Revert) {
    if (-not $PSCmdlet.ShouldProcess('Revert hotspot to Windows defaults (8/idle-off ON/Settings shown/no task)', 'Mobile Hotspot')) { return }
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\icssvc\Settings'
    # 1. Registry back to defaults (needs Admin).
    foreach ($name in @('WifiMaxPeers', 'PeerlessTimeoutEnabled')) {
        try {
            if (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $key -Name $name -Force -ErrorAction Stop
                Write-Host ("  removed {0} (back to Windows default)" -f $name)
            }
            else { Write-Host ("  {0} not present - already default" -f $name) }
        }
        catch { Write-Warning ("Could not remove {0} (need Admin): {1}" -f $name, $_.Exception.Message) }
    }
    try { Set-Service -Name 'icssvc' -StartupType Manual -ErrorAction Stop } catch { }
    try { Restart-Service -Name 'icssvc' -Force -ErrorAction Stop; Write-Host '  icssvc restarted' } catch { }
    # 2. Settings page back + task deleted (needs Admin).
    try {
        $pkey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        $pcur = (Get-ItemProperty -Path $pkey -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue).SettingsPageVisibility
        if ($null -ne $pcur -and $pcur -like '*network-mobilehotspot*') {
            $pnew = ($pcur -split ';' | Where-Object { $_ -ne 'network-mobilehotspot' -and $_ -ne 'hide:network-mobilehotspot' -and $_ -ne 'hide' }) -join ';'
            if ([string]::IsNullOrWhiteSpace($pnew)) { Remove-ItemProperty -Path $pkey -Name 'SettingsPageVisibility' -Force -ErrorAction Stop }
            else { New-ItemProperty -Path $pkey -Name 'SettingsPageVisibility' -PropertyType String -Value $pnew -Force -ErrorAction Stop | Out-Null }
        }
        Write-Host '  Settings hotspot page unhidden.'
        Unregister-ScheduledTask -TaskName 'AutoHotspot-UUID' -Confirm:$false -ErrorAction Stop
        Write-Host '  auto-start task deleted.'
    }
    catch { Write-Warning ("Task/policy revert needs Admin: {0}" -f $_.Exception.Message) }
    # 3. Hotspot config back to Windows style: PC name + random password, Auto.
    try { Await-Action ($manager.StopTetheringAsync()) } catch { }
    $def = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration]::new()
    $def.Ssid = $env:COMPUTERNAME
    $def.Passphrase = (-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ }))
    $def.Band = 0
    Await-Action ($manager.ConfigureAccessPointAsync($def))
    Write-Host ("  hotspot reset to defaults: SSID '{0}' on Auto band, hotspot OFF." -f $env:COMPUTERNAME)
    Write-Host ("  new random password: {0} (save it - turn hotspot on from Settings to use)" -f $def.Passphrase)
    Write-Host 'Reverted.' -ForegroundColor Green
    Show-Current $manager
    if ($Reboot) { Invoke-RebootCountdown $RebootDelaySeconds }
    return
}

if ($LockPassword -and $UnlockPassword) { throw 'Cannot combine -LockPassword with -UnlockPassword.' }

if ($LockPassword) {
    if (-not $PSCmdlet.ShouldProcess('Hotspot password lock (hide Settings + SYSTEM enforcement)', 'Mobile Hotspot')) { return }
    Ensure-ClientLimit32 | Out-Null
    try {
        Lock-HotspotPassword -ScriptPath $PSCommandPath -TaskSsid $Ssid -TaskBand $Band
        Write-Host 'Locked: password changes now need Admin (Settings hidden, SYSTEM reverts every 5 min).' -ForegroundColor Green
    }
    catch { throw }
    Show-Current $manager
    return
}

if ($UnlockPassword) {
    if (-not $PSCmdlet.ShouldProcess('Hotspot password unlock', 'Mobile Hotspot')) { return }
    try {
        Unlock-HotspotPassword -ScriptPath $PSCommandPath -TaskSsid $Ssid -TaskBand $Band
        Write-Host 'Unlocked.' -ForegroundColor Green
    }
    catch { throw }
    Show-Current $manager
    return
}

$action = "Create hotspot '$Ssid' (5GHz/32 clients) and auto-start"
if (-not $PSCmdlet.ShouldProcess($action, 'Mobile Hotspot')) { return }

# --- enforce 32-client limit -------------------------------------------------
Ensure-ClientLimit32 | Out-Null

# --- enforce always-on: PeerlessTimeoutEnabled=0 kills the idle auto-off -----
# Must run BEFORE the guard: it restarts icssvc when the value changed, and
# the guard below then (re)starts tethering on the fresh service.
Ensure-IdleAlwaysOn | Out-Null

# --- 5-min guard: skip restart when everything already matches ----------------
# The SYSTEM task runs this script every 5 min. Restarting unconditionally
# would kick all clients each time, so only configure/start on drift or Off.
$wantBand = Get-BandValue $Band
$curCfg = $null
try { $curCfg = $manager.GetCurrentAccessPointConfiguration() } catch { }
$curState = $manager.TetheringOperationalState.ToString()
$needsConfig = $true
$needsStart = ($curState -ne 'On')
if ($null -ne $curCfg) {
    $needsConfig = ($curCfg.Ssid -ne $Ssid) -or ($curCfg.Passphrase -ne $Password) -or ([int]$curCfg.Band -ne $wantBand)
}
if (-not $needsConfig -and -not $needsStart) {
    Write-Host ("  guard: hotspot already ON with SSID '{0}' (5GHz/12345678). No restart." -f $Ssid) -ForegroundColor Green
}
else {
    if ($needsConfig) {
        Write-Host ("  guard: drift detected (state={0}) - reconfiguring." -f $curState)
    }
    else {
        Write-Host '  guard: hotspot is OFF - starting it.'
    }

# --- configure -------------------------------------------------------------
$config = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration]::new()
$config.Ssid = $Ssid
$config.Passphrase = $Password
try { $config.Band = $wantBand } catch { Write-Warning "Could not set band $Band, leaving default." }

if ($needsConfig) {
    $cfgOp = $manager.ConfigureAccessPointAsync($config)
    Await-Action $cfgOp
    Write-Host '  configure: Success'
}
Write-Host ("  SSID: {0}" -f $Ssid)
Write-Host '  password: ******** (8 chars, as requested)'

# --- auto-start ------------------------------------------------------------
if (-not $NoStart -and ($needsStart -or $needsConfig)) {
    try { Await-Action ($manager.StopTetheringAsync()) } catch { }
    $resultType = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult]
    $startStatus = Await-Op ($manager.StartTetheringAsync()) $resultType
    Write-Host ("  start: {0}" -f $startStatus.Status)
    if ($startStatus.Status.ToString() -ne 'Success' -and $startStatus.Status.ToString() -ne 'AlreadyOn') {
        throw ("StartTetheringAsync failed: {0} {1}" -f $startStatus.Status, $startStatus.AdditionalErrorMessage)
    }
    Write-Host ("Result: hotspot '{0}' is ON." -f $Ssid) -ForegroundColor Green
}
elseif ($NoStart) {
    Write-Host 'Configured only (-NoStart given). Turn it on from Settings or re-run without -NoStart.'
}
} # end guard else

# (Idle auto-off is handled above by Ensure-IdleAlwaysOn; the 5-min SYSTEM
# guard below remains as backup for human OFF toggles.)

# --- persistent auto-start + lock by default -------------------------------------
# Default every run: hide Settings hotspot page + SYSTEM task every 5 min so
# password changes need Admin, any API change is reverted fast, and a hotspot
# someone turned OFF is restarted within 5 min (guard above skips restart
# when already ON with correct config, so clients are not kicked).
# Standalone: no dependency on Set-HotspotClientLimit.ps1 — limit + task logic
# is embedded above (Ensure-ClientLimit32, Lock-HotspotPassword).
if (-not $NoAutoTask -and -not $NoStart) {
    try {
        Lock-HotspotPassword -ScriptPath $PSCommandPath -TaskSsid $Ssid -TaskBand $Band
    }
    catch {
        Write-Warning ("Lock needs Admin ({0}). Falling back to user task." -f $_.Exception.Message)
        try {
            Ensure-AutoTask -TaskSsid $Ssid -TaskPassword $Password -TaskBand $Band -ScriptPath $PSCommandPath
        }
        catch {
            Write-Warning ("Could not install auto-start task (need Admin): {0}" -f $_.Exception.Message)
        }
    }
}
elseif ($InstallAutoTask -or $LockPassword) {
    # Backward compat: explicit flags still work when -NoAutoTask is also passed.
    try {
        Lock-HotspotPassword -ScriptPath $PSCommandPath -TaskSsid $Ssid -TaskBand $Band
    }
    catch {
        Write-Warning ("Lock needs Admin ({0})." -f $_.Exception.Message)
    }
}

Show-Current $manager
Write-RunLog ("run ok state={0} ssid={1}" -f $manager.TetheringOperationalState.ToString(), $Ssid)

# --- auto-reboot: default ON for manual runs, never for task runs --------------
# Scheduled task always passes -NoAutoTask (and -NoReboot), so it never reboots.
# Manual run reboots unless -NoReboot / -Show / -Stop / -NoStart / -Revert / -Help.
$IsWorkflowRun = (-not $Show -and -not $Stop -and -not $Help -and -not $Revert -and -not $NoStart -and -not $NoAutoTask)
$ShouldReboot = ($Reboot -or ((-not $NoReboot) -and $IsWorkflowRun))
if ($Reboot -and $NoReboot) { throw 'Cannot combine -Reboot with -NoReboot.' }
if ($ShouldReboot) { Invoke-RebootCountdown $RebootDelaySeconds }
