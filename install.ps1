<#
.SYNOPSIS
  One-shot installer for a new Windows PC (AMD64 or ARM64). Installs everything the test system
  needs, then checks the PC, the apps under test and any connected phone, and prints what is left
  to do by hand.

  What it installs (no admin rights needed, nothing added to the system PATH):
    - Python (pinned in setup\versions.json -> python_install) for the current user, only if no
      Python 3.10+ is found
    - Everything in setup\setup.ps1: Microsoft OpenJDK 17, Maestro CLI, a Python venv with the
      pinned uiautomation / comtypes / PyYAML, Android platform-tools (adb)
  What it only checks (cannot be installed from here):
    - The apps listed in apps.json (Windows Store app / phone package)
    - Phone setup: USB debugging authorised, Developer options, Xiaomi "Install via USB" and
      "USB debugging (Security settings)", Maestro driver on the phone

.EXAMPLE
  install.cmd                                         # double-click, or:
  powershell -ExecutionPolicy Bypass -File install.ps1
  powershell -ExecutionPolicy Bypass -File install.ps1 -Smoke     # also run one PC and one phone test
  powershell -ExecutionPolicy Bypass -File install.ps1 -Force     # reinstall the toolchain
  powershell -ExecutionPolicy Bypass -File install.ps1 -CheckOnly # only run the checks
#>
param(
    [switch]$Force,
    [switch]$Smoke,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # PS 5.1 downloads are many times slower with the progress bar on
$Root = $PSScriptRoot
. (Join-Path $Root 'tools\common.ps1')

$todo = New-Object System.Collections.ArrayList
function Ok([string]$m)   { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "  [todo] $m" -ForegroundColor Yellow; [void]$todo.Add($m) }
function Info([string]$m) { Write-Host "         $m" }
function Head([string]$m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }

# --- 1. PC preflight ----------------------------------------------------------
Head 'PC'
$arch = Get-PcArch
$os = Get-CimInstance Win32_OperatingSystem
Ok ("{0} build {1}, {2}, PowerShell {3}" -f $os.Caption, $os.BuildNumber, $arch, $PSVersionTable.PSVersion)
if ([int]$os.BuildNumber -lt 17763) { throw 'Windows 10 1809 or newer is required.' }
if ($Root -match '[^\x00-\x7F]') { Warn "The repo path has non-ASCII characters ($Root); move it to a plain path if tools fail." }

# Files copied from a zip/download carry "Mark of the Web"; unblock so scripts run without prompts
Get-ChildItem $Root -Recurse -Include *.ps1, *.py, *.cmd -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "$ToolsDir*" } | Unblock-File -ErrorAction SilentlyContinue

if (-not $CheckOnly) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $null = Invoke-WebRequest -Uri 'https://www.python.org' -Method Head -UseBasicParsing -TimeoutSec 15
        Ok 'Internet reachable'
    } catch { throw "No internet access (python.org not reachable): $($_.Exception.Message)" }
}

# --- 2. Python ---------------------------------------------------------------
function Find-Python {
    $min = [version]$Versions.python_min
    $cands = @(@('py', '-3'), @('python'))
    $known = @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | ForEach-Object { , @($_.FullName) })
    foreach ($cand in ($cands + $known)) {
        $cmd = Get-Command $cand[0] -ErrorAction SilentlyContinue
        if (-not $cmd -or $cmd.Source -like '*WindowsApps*') { continue }
        $a = @($cand | Select-Object -Skip 1)
        $ErrorActionPreference = 'Continue'
        $ver = & $cmd.Source @a -c 'import sys; print(''%d.%d.%d'' % sys.version_info[:3])' 2>$null
        $ErrorActionPreference = 'Stop'
        if ($ver -and ([version]$ver -ge $min)) { return "$($cmd.Source) ($ver)" }
    }
    return $null
}

Head 'Python'
$found = Find-Python
if ($found) {
    Ok "Python found: $found"
} elseif ($CheckOnly) {
    Warn "Python $($Versions.python_min)+ not installed (run install.ps1 without -CheckOnly)"
} else {
    $pv = $Versions.python_install
    $parch = if ($arch -eq 'arm64') { 'arm64' } else { 'amd64' }
    $url = "https://www.python.org/ftp/python/$pv/python-$pv-$parch.exe"
    $dl = Join-Path $ToolsDir '_downloads'
    New-Item -ItemType Directory -Force $dl | Out-Null
    $exe = Join-Path $dl "python-$pv-$parch.exe"
    if (-not (Test-Path $exe)) {
        Info "downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
    }
    $sig = Get-AuthenticodeSignature $exe
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Python Software Foundation') {
        throw "Python installer signature check failed ($($sig.Status), $($sig.SignerCertificate.Subject))"
    }
    Info "installing Python $pv ($parch) for the current user (silent, about 1-2 minutes)"
    $p = Start-Process -FilePath $exe -Wait -PassThru -ArgumentList @(
        '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1', 'InstallLauncherAllUsers=0',
        'Include_test=0', 'Include_doc=0', 'Include_tcltk=0', 'Shortcuts=0')
    if ($p.ExitCode -ne 0) { throw "Python installer exited with code $($p.ExitCode)" }
    $found = Find-Python
    if (-not $found) { throw 'Python was installed but cannot be found; open a new PowerShell window and run install.ps1 again.' }
    Ok "Python installed: $found"
}

# --- 3. Toolchain (JDK, Maestro, venv + packages, adb) -------------------------
Head 'Toolchain (setup\setup.ps1)'
if ($CheckOnly) {
    foreach ($t in 'java', 'maestro', 'python', 'adb') {
        if (Test-Path (Get-ToolPath $t)) { Ok "$t present" } else { Warn "$t missing (run install.ps1)" }
    }
} else {
    $sArgs = @{}
    if ($Force) { $sArgs.Force = $true }
    & (Join-Path $Root 'setup\setup.ps1') @sArgs
}

# Self-test of the Python side: imports and selector parser
$py = Get-ToolPath 'python'
if (Test-Path $py) {
    $env:PYTHONIOENCODING = 'utf-8'
    $ErrorActionPreference = 'Continue'
    Push-Location $Root
    $chk = & $py -c 'import sys; sys.path.insert(0, ''tools''); import wincore, yaml; wincore.parse(''role:Button && name:OK >> id:1''); print(''ok'')' 2>&1
    Pop-Location
    $ErrorActionPreference = 'Stop'
    if ("$chk" -match 'ok$') { Ok 'Windows runner imports and parses selectors' } else { Warn "Windows runner self-test failed: $chk" }
}

# --- 4. Apps under test on this PC --------------------------------------------
Head 'Apps on this PC (apps.json)'
$Apps = Get-Content (Join-Path $Root 'apps.json') -Raw | ConvertFrom-Json
foreach ($name in $Apps.PSObject.Properties.Name) {
    $w = $Apps.$name.windows
    if (-not $w) { continue }
    $pkg = Get-AppxPackage -Name $w.appx -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) { Ok "$name $($pkg.Version)" } else { Warn "$name is not installed on this PC (Appx '$($w.appx)'); install it before running its Windows tests" }
}
foreach ($s in 'bluetooth', 'dark-mode') {
    $f = Join-Path $Root "windows\settings\$s.ps1"
    if (-not (Test-Path $f)) { continue }
    try { $val = (& $f -Action get | Out-String).Trim(); Ok "setting $s readable ($val)" }
    catch { Warn "windows setting $s cannot be read: $($_.Exception.Message)" }
}

# --- 5. Phones ------------------------------------------------------------------
Head 'Phones (adb)'
$adb = Get-ToolPath 'adb'
if (-not (Test-Path $adb)) {
    Warn 'adb missing'
} else {
    $lines = @((Invoke-Adb '' @('devices')) -split "`n" | Where-Object { $_ -match '^\S+\s+(device|unauthorized|offline)\s*$' })
    if (-not $lines) {
        Warn 'No phone connected. Connect it by USB, turn on Developer options + USB debugging, then run: install.ps1 -CheckOnly'
    }
    $Devices = $null
    $df = Join-Path $Root 'devices.json'
    if (Test-Path $df) { $Devices = Get-Content $df -Raw | ConvertFrom-Json }
    foreach ($l in $lines) {
        $ser, $state = ($l.Trim() -split '\s+')[0, 1]
        if ($state -ne 'device') { Warn "$ser is '$state': unlock the phone and tap Allow on the USB debugging prompt"; continue }
        $p = Get-AndroidProfile $ser
        Ok ("{0}: {1} {2} ({3}), Android {4}, skin {5}, locale {6}" -f $ser, $p.brand, $p.market_name, $p.model, $p.android_version, $p.skin, $p.locale)
        $sh = { param($c) (Invoke-Adb $ser @('shell', $c)).Trim() }
        if ((& $sh 'settings get global development_settings_enabled') -ne '1') { Warn "$ser Developer options are off" }
        if ($p.brand -eq 'xiaomi') {
            if ((& $sh 'getprop persist.security.adbinstall') -ne '1') { Warn "$ser Xiaomi: turn on Developer options > Install via USB" }
            if ((& $sh 'getprop persist.security.adbinput') -ne '1') {
                Warn "$ser Xiaomi: turn on Developer options > USB debugging (Security settings) (needs Mi account); taps fail without it"
            } else { Ok "$ser Xiaomi security settings on (install + input)" }
        }
        $pk = & $sh 'pm list packages dev.mobile.maestro'
        if ($pk -match 'dev\.mobile\.maestro') {
            Ok "$ser Maestro driver installed"
        } else {
            Warn "$ser Maestro driver not installed yet: run any phone test while watching the phone and tap Install on both prompts"
        }
        foreach ($name in $Apps.PSObject.Properties.Name) {
            $a = $Apps.$name.android
            if (-not $a) { continue }
            $d = Invoke-Adb $ser @('shell', 'dumpsys', 'package', $a.package)
            $m = [regex]::Match($d, 'versionName=([^\r\n]+)')
            if ($m.Success) { Ok "$ser $name $($m.Groups[1].Value.Trim())" } else { Warn "$ser $name not installed (package $($a.package))" }
        }
        if (-not ($Devices -and $Devices.$ser)) {
            Warn "$ser has no entry in devices.json (copy devices.example.json); add its Quick Share name (Quick Share > 'You'll appear as') for cross-device tests"
        }
        $guide = Get-ChildItem (Join-Path $Root "guides\system\android") -Filter "$($p.brand)-*.md" -ErrorAction SilentlyContinue
        if (-not $guide) { Warn "no system guide for brand '$($p.brand)' yet: start guides\system\android\$($p.brand)-<skin>.md" }
    }
}

# --- 6. Optional smoke tests ----------------------------------------------------
if ($Smoke) {
    Head 'Smoke tests'
    $run = Join-Path $Root 'tools\run.ps1'
    $tests = @('windows\workflows\quick-share\WTC-101-home-screen.yml', 'android\flows\quick-share\TC-101-main-screen.yaml')
    foreach ($t in $tests) {
        if (-not (Test-Path (Join-Path $Root $t))) { continue }
        $ErrorActionPreference = 'Continue'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $run -Test (Join-Path $Root $t) | Out-Host
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($code -eq 0) { Ok "$t passed" } else { Warn "$t failed (see results\)" }
    }
}

# --- Summary -------------------------------------------------------------------------
Head 'Summary'
if ($todo.Count -eq 0) {
    Write-Host '  Everything is installed and ready. Start with GUIDE.md.' -ForegroundColor Green
} else {
    Write-Host "  Installed what can be installed. $($todo.Count) item(s) need you:" -ForegroundColor Yellow
    $i = 0
    foreach ($t in $todo) { $i++; Write-Host "   $i. $t" }
    Write-Host '  Then re-check with: powershell -ExecutionPolicy Bypass -File install.ps1 -CheckOnly'
}
