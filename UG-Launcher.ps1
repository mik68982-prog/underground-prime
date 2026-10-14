#Requires -Version 5.1
<#
  Project UndergroundPrime — Online Launcher
  Usage (after host on GitLab/GitHub raw):
    iex (irm 'https://gitlab.com/USER/REPO/-/raw/main/UG-Launcher.ps1')

  Flow: Admin → KeyAuth login UI → load & run main script
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ===================== CONFIG (edit before host) =====================
$AppName    = 'UDGP'
$OwnerId    = 'cmHmlP3Wjd'
$AppVersion = '1.0'
# Optional: secret not required for init/license on 1.2 public flow
# $AppSecret = '...'

# After login, main script source (first match wins):
# 1) same folder as this launcher (local / after download)
# 2) MAIN_URL remote raw
$MainFileName = 'Project UndergroundPrime.ps1'
$MainUrl = 'https://raw.githubusercontent.com/mik68982-prog/underground-prime/main/Project%20UndergroundPrime.ps1'

$ApiBase = 'https://keyauth.win/api/1.2/'
# =====================================================================

$Host.UI.RawUI.WindowTitle = 'Project UndergroundPrime'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminRelaunch {
    $cmd = if ($PSCommandPath) {
        "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        # running from iex (irm ...) — re-fetch same pattern if set
        $u = $env:UG_LAUNCHER_URL
        if ($u) {
            "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm '$u')`""
        } else {
            "-NoProfile -ExecutionPolicy Bypass -Command `"Write-Host 'Please re-run launcher as Administrator' -ForegroundColor Red; pause`""
        }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $psi.Arguments = $cmd
    $psi.Verb      = 'runas'
    try {
        [Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show('Administrator permission is required.', 'UndergroundPrime') | Out-Null
    }
    exit 0
}

function Get-Hwid {
    try {
        $s = (Get-CimInstance Win32_ComputerSystemProduct -EA SilentlyContinue).UUID
        if ($s) { return ($s -replace '[^A-Za-z0-9]', '').ToUpperInvariant() }
    } catch {}
    try {
        $s = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -EA SilentlyContinue).MachineGuid
        if ($s) { return ($s -replace '[^A-Za-z0-9]', '').ToUpperInvariant() }
    } catch {}
    return ($env:COMPUTERNAME + $env:USERNAME).ToUpperInvariant()
}

function Invoke-KeyAuth {
    param([hashtable]$Query)
    $pairs = foreach ($k in $Query.Keys) {
        '{0}={1}' -f [uri]::EscapeDataString([string]$k), [uri]::EscapeDataString([string]$Query[$k])
    }
    $url = $ApiBase.TrimEnd('/') + '/?' + ($pairs -join '&')
    $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
    return $resp
}

function Initialize-KeyAuth {
    $r = Invoke-KeyAuth -Query @{
        type    = 'init'
        ver     = $AppVersion
        name    = $AppName
        ownerid = $OwnerId
    }
    if (-not $r.success) {
        throw ("KeyAuth init failed: {0}" -f $r.message)
    }
    return [string]$r.sessionid
}

function Test-KeyAuthLicense {
    param([string]$SessionId, [string]$Key)
    $r = Invoke-KeyAuth -Query @{
        type      = 'license'
        key       = $Key
        sessionid = $SessionId
        name      = $AppName
        ownerid   = $OwnerId
        hwid      = (Get-Hwid)
    }
    return $r
}

function Find-MainScript {
    $candidates = @()
    if ($PSScriptRoot) {
        $candidates += (Join-Path $PSScriptRoot $MainFileName)
    }
    try {
        $candidates += (Join-Path (Get-Location).Path $MainFileName)
    } catch {}
    $candidates += (Join-Path $env:TEMP $MainFileName)
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return $null
}

function Get-MainScriptText {
    $local = Find-MainScript
    if ($local) {
        return @{ Path = $local; Text = $null }
    }
    if ($MainUrl -and $MainUrl.Trim().Length -gt 8) {
        Write-Host '  Downloading main script...' -ForegroundColor DarkGray
        $txt = Invoke-WebRequest -Uri $MainUrl -UseBasicParsing -TimeoutSec 120 | Select-Object -ExpandProperty Content
        $path = Join-Path $env:TEMP $MainFileName
        # UTF-8 with BOM for PS 5.1
        $utf8bom = New-Object System.Text.UTF8Encoding $true
        [IO.File]::WriteAllText($path, $txt, $utf8bom)
        return @{ Path = $path; Text = $txt }
    }
    throw "Main script not found. Place '$MainFileName' next to launcher or set `$MainUrl in UG-Launcher.ps1"
}

function Show-LoginUi {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Project UndergroundPrime'
    $form.Size = New-Object System.Drawing.Size(420, 260)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 20)
    $form.ForeColor = [System.Drawing.Color]::WhiteSmoke
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Project UndergroundPrime'
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(24, 20)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(51, 253, 0)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = 'Enter license key'
    $sub.AutoSize = $true
    $sub.Location = New-Object System.Drawing.Point(26, 54)
    $sub.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 160)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(28, 88)
    $tb.Size = New-Object System.Drawing.Size(350, 28)
    $tb.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 36)
    $tb.ForeColor = [System.Drawing.Color]::White
    $tb.BorderStyle = 'FixedSingle'

    $status = New-Object System.Windows.Forms.Label
    $status.Text = ''
    $status.AutoSize = $false
    $status.Size = New-Object System.Drawing.Size(350, 40)
    $status.Location = New-Object System.Drawing.Point(28, 122)
    $status.ForeColor = [System.Drawing.Color]::FromArgb(200, 80, 80)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Login'
    $btn.Size = New-Object System.Drawing.Size(120, 34)
    $btn.Location = New-Object System.Drawing.Point(28, 170)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 44)
    $btn.ForeColor = [System.Drawing.Color]::FromArgb(51, 253, 0)
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(51, 253, 0)

    $script:AuthOk = $false
    $script:SessionId = $null

    $doLogin = {
        $status.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
        $status.Text = 'Connecting...'
        $form.Refresh()
        $key = $tb.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            $status.ForeColor = [System.Drawing.Color]::FromArgb(200, 80, 80)
            $status.Text = 'Please enter a key.'
            return
        }
        try {
            if (-not $script:SessionId) {
                $script:SessionId = Initialize-KeyAuth
            }
            $r = Test-KeyAuthLicense -SessionId $script:SessionId -Key $key
            if ($r.success -eq $true -or $r.success -eq 'true' -or $r.success -eq 1) {
                $script:AuthOk = $true
                $status.ForeColor = [System.Drawing.Color]::FromArgb(51, 253, 0)
                $status.Text = 'OK — starting...'
                $form.Refresh()
                Start-Sleep -Milliseconds 400
                $form.Close()
            } else {
                $status.ForeColor = [System.Drawing.Color]::FromArgb(200, 80, 80)
                $status.Text = [string]$r.message
                if (-not $status.Text) { $status.Text = 'Invalid key.' }
                # new session next try if session burned
                try { $script:SessionId = Initialize-KeyAuth } catch { $script:SessionId = $null }
            }
        } catch {
            $status.ForeColor = [System.Drawing.Color]::FromArgb(200, 80, 80)
            $status.Text = $_.Exception.Message
            $script:SessionId = $null
        }
    }

    $btn.Add_Click($doLogin)
    $tb.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq 'Enter') { & $doLogin }
    })

    $form.Controls.AddRange(@($title, $sub, $tb, $status, $btn))
    $form.AcceptButton = $btn
    [void]$form.ShowDialog()
    return [bool]$script:AuthOk
}

# -------------------- main --------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
} catch {}

if (-not (Test-IsAdmin)) {
    Request-AdminRelaunch
}

Write-Host ''
Write-Host '  Project UndergroundPrime Launcher' -ForegroundColor Green
Write-Host ''

$ok = $false
try {
    $ok = Show-LoginUi
} catch {
    Write-Host ("  UI/Auth error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    try {
        # console fallback
        Write-Host '  Fallback console login' -ForegroundColor Yellow
        $sid = Initialize-KeyAuth
        $key = Read-Host '  License key'
        $r = Test-KeyAuthLicense -SessionId $sid -Key $key
        if ($r.success -eq $true -or $r.success -eq 'true') { $ok = $true }
        else { Write-Host ("  {0}" -f $r.message) -ForegroundColor Red }
    } catch {
        Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

if (-not $ok) {
    Write-Host '  Login cancelled or failed.' -ForegroundColor Red
    Start-Sleep -Seconds 2
    exit 1
}

Write-Host '  Authenticated. Loading...' -ForegroundColor Green
try {
    $main = Get-MainScriptText
    $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$($main.Path)`""
    Start-Process -FilePath $psExe -ArgumentList $arg -Wait
} catch {
    Write-Host ("  Failed to start main: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Start-Sleep -Seconds 4
    exit 1
}

exit 0
