<#
.SYNOPSIS
  Installs the pinned toolchain into .tools\ for this PC's architecture (AMD64 or ARM64).
  No admin rights needed; nothing is added to the system PATH.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup\setup.ps1
  powershell -ExecutionPolicy Bypass -File setup\setup.ps1 -Force   # reinstall
#>
param([switch]$Force)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\common.ps1')
$ProgressPreference = 'SilentlyContinue'   # PS 5.1 downloads are many times slower with the progress bar on

$arch = Get-PcArch
$v = $script:Versions
New-Item -ItemType Directory -Force $ToolsDir | Out-Null
$dl = Join-Path $ToolsDir '_downloads'
New-Item -ItemType Directory -Force $dl | Out-Null

function Get-File([string]$Url, [string]$Name) {
    $dest = Join-Path $dl $Name
    if ((Test-Path $dest) -and -not $Force) { return $dest }
    Write-Host "  downloading $Url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
    return $dest
}

function Expand-To([string]$Zip, [string]$Dest) {
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    Expand-Archive -Path $Zip -DestinationPath $Dest -Force
}

Write-Host "PC architecture: $arch"

# --- JDK (Microsoft Build of OpenJDK, portable zip) ---------------------------
$java = Get-ToolPath 'java'
if ($Force -or -not (Test-Path $java)) {
    Write-Host "Installing Microsoft OpenJDK $($v.jdk) ($arch)"
    $jarch = if ($arch -eq 'arm64') { 'aarch64' } else { 'x64' }
    $zip = Get-File "https://aka.ms/download-jdk/microsoft-jdk-$($v.jdk)-windows-$jarch.zip" "jdk-$($v.jdk)-$jarch.zip"
    $tmp = Join-Path $ToolsDir '_jdk_tmp'
    Expand-To $zip $tmp
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    $target = Join-Path $ToolsDir "jdk-$($v.jdk)"
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Move-Item $inner.FullName $target
    Remove-Item -Recurse -Force $tmp
}

# --- Maestro CLI (JVM, same zip for both architectures) -----------------------
$maestro = Get-ToolPath 'maestro'
if ($Force -or -not (Test-Path $maestro)) {
    Write-Host "Installing Maestro $($v.maestro)"
    $base = "https://github.com/mobile-dev-inc/maestro/releases/download/cli-$($v.maestro)"
    $zip = Get-File "$base/maestro.zip" "maestro-$($v.maestro).zip"
    $sums = Get-File "$base/checksums_sha256.txt" "maestro-$($v.maestro)-checksums.txt"
    $expected = (Get-Content $sums | Where-Object { $_ -match 'maestro\.zip' } | Select-Object -First 1) -split '\s+' | Select-Object -First 1
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($expected -and ($expected.ToLower() -ne $actual.ToLower())) { throw "Maestro checksum mismatch: $actual vs $expected" }
    Expand-To $zip (Join-Path $ToolsDir "maestro-$($v.maestro)")
}

# --- Python venv with pinned Windows UI Automation packages ------------------
$py = Get-ToolPath 'python'
$reqs = @($v.pip.PSObject.Properties | ForEach-Object { "$($_.Name)==$($_.Value)" })
if ($Force -or -not (Test-Path $py)) {
    $base = $null
    # PATH first, then the per-user / all-users python.org locations (a fresh install is not on PATH yet)
    $cands = @(@('py', '-3'), @('python'))
    $known = @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | ForEach-Object { , @($_.FullName) })
    foreach ($cand in ($cands + $known)) {
        $cmd = Get-Command $cand[0] -ErrorAction SilentlyContinue
        if (-not $cmd -or $cmd.Source -like '*WindowsApps*') { continue }   # skip the Store alias stub
        $pyArgs = @($cand | Select-Object -Skip 1)
        # No double quotes inside -c: PowerShell 5.1 strips them when calling native programs.
        $ErrorActionPreference = 'Continue'
        $ver = & $cmd.Source @pyArgs -c 'import sys; print(''%d.%d'' % sys.version_info[:2])' 2>$null
        $ErrorActionPreference = 'Stop'
        if ($ver -and ([version]$ver -ge [version]$v.python_min)) { $base = @($cmd.Source) + $pyArgs; break }
    }
    if (-not $base) {
        throw "Python $($v.python_min)+ not found. Run install.ps1 (it installs Python $($v.python_install)) or install a native $arch build from python.org."
    }
    Write-Host "Creating Python venv with $($base -join ' ')"
    $exe = $base[0]; $rest = @($base | Select-Object -Skip 1)
    if (Test-Path (Join-Path $ToolsDir 'venv')) { Remove-Item -Recurse -Force (Join-Path $ToolsDir 'venv') }
    & $exe @rest -m venv (Join-Path $ToolsDir 'venv')
    if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
}
Write-Host "Installing Python packages: $($reqs -join ', ')"
& $py -m pip install --disable-pip-version-check -q @reqs
if ($LASTEXITCODE -ne 0) { throw 'pip install failed' }

# --- adb ----------------------------------------------------------------------
$adb = Get-ToolPath 'adb'
if (-not (Test-Path $adb)) {
    # Google ships only an x64 build; on ARM64 it runs under x64 emulation.
    Write-Host 'Installing Android platform-tools'
    $zip = Get-File 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' 'platform-tools.zip'
    Expand-Archive -Path $zip -DestinationPath $ToolsDir -Force
    $adb = Get-ToolPath 'adb'
}

# --- Report -------------------------------------------------------------------
Use-PinnedJava
$ErrorActionPreference = 'Continue'   # java/maestro print versions on stderr
Write-Host ''
Write-Host 'Installed:'
Write-Host ("  java       " + ((& $java -version 2>&1 | Select-Object -First 1) -as [string]))
Write-Host ("  maestro    " + ((& $maestro --version 2>&1 | Select-Object -Last 1) -as [string]))
Write-Host ("  python     " + ((& $py -c 'import sys,platform,uiautomation; print(sys.version.split()[0], platform.machine(), ''uiautomation'', uiautomation.VERSION)' 2>&1) -as [string]))
Write-Host ("  adb        " + ((& $adb version 2>&1 | Select-Object -First 1) -as [string]) + "  [$adb]")
Write-Host ''
Write-Host 'Devices:'
& $adb devices -l
