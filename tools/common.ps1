# Shared helpers. Dot-source from other scripts:  . "$PSScriptRoot\common.ps1"
# Works on Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:ToolsDir = Join-Path $RepoRoot '.tools'
$script:Versions = Get-Content (Join-Path $RepoRoot 'setup\versions.json') -Raw | ConvertFrom-Json

function Get-PcArch {
    # PROCESSOR_ARCHITEW6432 is set when an x64 process runs emulated on ARM64.
    $a = $env:PROCESSOR_ARCHITEW6432
    if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
    if ($a -eq 'ARM64') { return 'arm64' }
    return 'amd64'
}

function Get-ToolPath([string]$Name) {
    $v = $script:Versions
    switch ($Name) {
        'java'       { return Join-Path $ToolsDir "jdk-$($v.jdk)\bin\java.exe" }
        'maestro'    { return Join-Path $ToolsDir "maestro-$($v.maestro)\maestro\bin\maestro.bat" }
        'python'     { return Join-Path $ToolsDir 'venv\Scripts\python.exe' }
        'adb' {
            $local = Join-Path $ToolsDir 'platform-tools\adb.exe'
            if (Test-Path $local) { return $local }
            $cmd = Get-Command adb -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
            return $local
        }
        default { throw "Unknown tool: $Name" }
    }
}

function Use-PinnedJava {
    # Maestro reads JAVA_HOME; point it at the pinned JDK for this process only.
    $java = Get-ToolPath 'java'
    if (-not (Test-Path $java)) { throw "Pinned JDK missing. Run setup\setup.ps1 first." }
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $java)
    $env:MAESTRO_CLI_NO_ANALYTICS = '1'
    $env:MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED = 'true'
}

function Invoke-Adb([string]$Serial, [string[]]$AdbArgs) {
    $adb = Get-ToolPath 'adb'
    $all = @()
    if ($Serial) { $all += @('-s', $Serial) }
    $all += $AdbArgs
    # adb writes progress to stderr; in PS 5.1 that must not become a terminating error
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & $adb @all 2>&1 } finally { $ErrorActionPreference = $prev }
    return ($out | ForEach-Object { "$_" }) -join "`n"
}

function Resolve-Serial([string]$Serial) {
    if ($Serial) { return $Serial }
    $lines = (Invoke-Adb '' @('devices')) -split "`n" | Where-Object { $_ -match "^\S+\s+device\s*$" }
    if (@($lines).Count -eq 1) { return ($lines -split '\s+')[0] }
    if (@($lines).Count -eq 0) { throw 'No Android device connected (adb devices is empty).' }
    throw 'Several devices connected; pass -Serial.'
}

function Get-AndroidProfile([string]$Serial) {
    $p = { param($k) (Invoke-Adb $Serial @('shell', 'getprop', $k)).Trim() }
    $manufacturer = & $p 'ro.product.manufacturer'
    [ordered]@{
        # BRAND is the manufacturer family (xiaomi covers Redmi/POCO), used for subflows/system/<brand>/
        brand           = $manufacturer.ToLower()
        sub_brand       = & $p 'ro.product.brand'
        model           = & $p 'ro.product.model'
        market_name     = & $p 'ro.product.marketname'
        android_version = & $p 'ro.build.version.release'
        skin            = & $p 'ro.mi.os.version.incremental'
        locale          = & $p 'persist.sys.locale'
        serial          = $Serial
    }
}

function Get-PcProfile {
    [ordered]@{
        arch          = Get-PcArch
        windows_build = "$([Environment]::OSVersion.Version.Build)"
        locale        = (Get-Culture).Name
    }
}

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
}
