<#
.SYNOPSIS
    One-line installer for New-AutoHotspot.ps1. Downloads, elevates, configures, reboots.

.DESCRIPTION
    THE ONE-LINE INSTALL
    --------------------
    Open PowerShell (Administrator is fine but not required) and run:

        curl.exe -sSL https://raw.githubusercontent.com/iamawanishmaurya/auto-hotspot/main/Install-AutoHotspot.ps1 | powershell -NoProfile -ExecutionPolicy Bypass -Command -

    or, without curl:

        irm https://raw.githubusercontent.com/iamawanishmaurya/auto-hotspot/main/Install-AutoHotspot.ps1 | iex

    That is the whole install. This script does everything else:

      1. Elevates    - relaunches itself as Administrator via UAC if needed.
      2. Downloads   - fetches New-AutoHotspot.ps1 to
                       %ProgramData%\AutoHotspot\New-AutoHotspot.ps1
      3. Unblocks    - strips Mark-of-the-Web so the unsigned script runs.
      4. Runs        - executes it as a FILE (not piped into iex, see below).
      5. Reboots     - countdown, then restart, to prove the boot task works.

    WHY THE PAYLOAD IS SAVED TO DISK AND RUN AS A FILE
    ---------------------------------------------------
    New-AutoHotspot.ps1 registers a scheduled task pointing at its own path
    via $PSCommandPath. When a script is piped into iex, $PSCommandPath is
    empty, and the task would be registered pointing at "" -- a task that
    silently never runs again. So the payload is always written to a stable,
    persistent location and invoked with -File. That is also why the path is
    %ProgramData% and not %TEMP%: Windows is free to clear TEMP, which would
    leave the scheduled task pointing at a file that no longer exists.

.PARAMETER Ssid
    Hotspot name. Defaults to the auto-generated UUID behaviour.

.PARAMETER Band
    Auto, 2.4GHz, 5GHz or 6GHz. Defaults to 5GHz.

.PARAMETER RebootDelaySeconds
    Countdown before the final reboot. Defaults to 30.

.PARAMETER NoReboot
    Configure and start the hotspot but do not reboot the machine.

.PARAMETER PayloadUrl
    Override the download URL. Useful for testing a fork or a local file.

.EXAMPLE
    irm https://raw.githubusercontent.com/iamawanishmaurya/auto-hotspot/main/Install-AutoHotspot.ps1 | iex

.EXAMPLE
    .\Install-AutoHotspot.ps1 -Band 2.4GHz -RebootDelaySeconds 60

.EXAMPLE
    .\Install-AutoHotspot.ps1 -NoReboot
#>
[CmdletBinding()]
param(
    [string]$Ssid = '',
    [ValidateSet('Auto', '2.4GHz', '5GHz', '6GHz')]
    [string]$Band = '5GHz',
    [ValidateRange(5, 300)]
    [int]$RebootDelaySeconds = 30,
    [switch]$NoReboot,
    [string]$PayloadUrl = 'https://raw.githubusercontent.com/iamawanishmaurya/auto-hotspot/main/New-AutoHotspot.ps1'
)

$ErrorActionPreference = 'Stop'
$script:InstallDir = Join-Path $env:ProgramData 'AutoHotspot'
$script:PayloadPath = Join-Path $script:InstallDir 'New-AutoHotspot.ps1'

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host ("==> {0}" -f $Message) -ForegroundColor Cyan
}

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- step 1: elevate --------------------------------------------------------
# Re-launch through UAC. When this script was piped in via iex there is no
# script file to re-run, so we re-fetch it from the same URL and pass the
# arguments along explicitly.
if (-not (Test-Administrator)) {
    Write-Step 'Administrator rights required'
    Write-Host '    Registry policy, scheduled task, and Settings hiding all need elevation.'
    Write-Host '    Click Yes on the User Account Control prompt.'

    $selfUrl = 'https://raw.githubusercontent.com/iamawanishmaurya/auto-hotspot/main/Install-AutoHotspot.ps1'
    # SSIDs may legitimately contain a single quote, which would otherwise close
    # the string early in the re-launched command. PowerShell escapes it by
    # doubling it inside a single-quoted literal.
    $ssidArg = $Ssid -replace "'", "''"
    $boot = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-Command'
        ("irm {0} | iex -Ssid '{1}' -Band {2} -RebootDelaySeconds {3} -PayloadUrl '{4}'{5}" -f
            $selfUrl, $ssidArg, $Band, $RebootDelaySeconds, $PayloadUrl,
            $(if ($NoReboot) { ' -NoReboot' } else { '' }))
    )

    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList $boot `
        -Verb RunAs `
        -WindowStyle Normal | Out-Null
    return
}

# --- step 2: download the payload -------------------------------------------
Write-Step 'Downloading New-AutoHotspot.ps1'
Write-Host ("    {0}" -f $PayloadUrl)

if (-not (Test-Path $script:InstallDir)) {
    New-Item -Path $script:InstallDir -ItemType Directory -Force | Out-Null
}

try {
    # TLS 1.2 for older Windows PowerShell defaults that still negotiate 1.0.
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $PayloadUrl -OutFile $script:PayloadPath -UseBasicParsing
}
catch {
    Write-Host ''
    Write-Host ("    Download failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host '    Check the URL and your internet connection, then try again.'
    Write-Host ''
    Read-Host '    Press Enter to close'
    exit 1
}

Write-Host ("    saved to {0} ({1} bytes)" -f $script:PayloadPath, (Get-Item $script:PayloadPath).Length)

# --- step 3: unblock (Mark-of-the-Web) --------------------------------------
Write-Step 'Unblocking script'
Unblock-File -LiteralPath $script:PayloadPath -ErrorAction SilentlyContinue
Write-Host '    Mark-of-the-Web removed; the unsigned script will run.'

# --- step 4: run the payload as a FILE --------------------------------------
# -File (not iex) is required: $PSCommandPath must be a real, stable path for
# the scheduled task it registers.
Write-Step 'Configuring hotspot'
Write-Host ('    SSID : {0}' -f $(if ($Ssid) { $Ssid } else { 'auto UUID (printed below)' }))
Write-Host ('    Band : {0}' -f $Band)
Write-Host ('    Pass : 12345678 (fixed)')
Write-Host ''

$payloadArgs = @('-NoReboot')
if ($Ssid) { $payloadArgs += @('-Ssid', $Ssid) }
$payloadArgs += @('-Band', $Band)

try {
    # -NoReboot here because this installer owns the final reboot, and the
    # payload would otherwise start its own countdown mid-configure.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:PayloadPath @payloadArgs
    $payloadExit = $LASTEXITCODE
}
catch {
    Write-Host ''
    Write-Host ("    Payload failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $payloadExit = 1
}

if ($payloadExit -ne 0) {
    Write-Host ''
    Write-Host ("    The hotspot script exited with code {0}." -f $payloadExit) -ForegroundColor Red
    Write-Host '    Nothing was rolled back. Re-run -Revert to undo, or fix the error above'
    Write-Host '    and run this installer again.'
    Write-Host ''
    Read-Host '    Press Enter to close'
    exit $payloadExit
}

# --- step 5: reboot ---------------------------------------------------------
if ($NoReboot) {
    Write-Step 'Done (no reboot requested)'
    Write-Host '    The hotspot is up and the boot+logon+5-minute task is installed.'
    Write-Host ''
    Read-Host '    Press Enter to close'
    exit 0
}

Write-Step 'Rebooting'
Write-Host '    This proves the hotspot comes back automatically on a cold boot.'
Write-Host '    The scheduled task starts it at boot, about 30 seconds after power-on.'
Write-Host ''
Write-Host ("    Rebooting in {0}s. Close anything unsaved. Press Ctrl+C to cancel." -f $RebootDelaySeconds) -ForegroundColor Yellow
for ($i = $RebootDelaySeconds; $i -gt 0; $i--) {
    Write-Host ("      {0,3}s ..." -f $i) -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host ''
Write-Host '    Rebooting now.'
Start-Sleep -Seconds 2
Restart-Computer -Force
