<#
.SYNOPSIS
  Print the current Android screen as a compact element list (one line per element).

.EXAMPLE
  tools\explore-android.ps1                       # only one phone connected
  tools\explore-android.ps1 -Serial <adb serial>
  tools\explore-android.ps1 -Source adb           # faster; uses uiautomator dump
  tools\explore-android.ps1 -All -Screenshot      # include unlabeled clickables, save a PNG
#>
param(
    [string]$Serial,
    [ValidateSet('maestro', 'adb')][string]$Source = 'maestro',
    [switch]$All,
    [switch]$Screenshot
)

. "$PSScriptRoot\common.ps1"
$Serial = Resolve-Serial $Serial
$tmp = Join-Path ([IO.Path]::GetTempPath()) "explore-android-$Serial"
New-Item -ItemType Directory -Force $tmp | Out-Null
$dump = Join-Path $tmp 'hierarchy.txt'

function Get-AdbDump {
    $null = Invoke-Adb $Serial @('shell', 'uiautomator', 'dump', '/sdcard/window_dump.xml')
    $null = Invoke-Adb $Serial @('pull', '/sdcard/window_dump.xml', $dump)
    $null = Invoke-Adb $Serial @('shell', 'rm', '/sdcard/window_dump.xml')
}

if ($Source -eq 'maestro') {
    Use-PinnedJava
    $maestro = Get-ToolPath 'maestro'
    $ErrorActionPreference = 'Continue'
    $out = & $maestro --device $Serial hierarchy --no-reinstall-driver 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = 'Stop'
    [IO.File]::WriteAllText($dump, ($out -join "`n"))
    if (-not (($out -join '') -match '"attributes"')) {
        Write-Warning 'maestro hierarchy failed; falling back to uiautomator dump'
        Get-AdbDump
    }
} else {
    Get-AdbDump
}

$focus = (Invoke-Adb $Serial @('shell', 'dumpsys', 'window')) -split "`n" |
    Where-Object { $_ -match 'mCurrentFocus=' } | Select-Object -First 1
Write-Output ("screen: " + ($focus -replace '.*mCurrentFocus=', '').Trim())

$py = Get-ToolPath 'python'
$pyArgs = @("$PSScriptRoot\androidtree.py", $dump)
if ($All) { $pyArgs += '--all' }
& $py @pyArgs

if ($Screenshot) {
    $png = Join-Path $tmp 'screen.png'
    $null = Invoke-Adb $Serial @('shell', 'screencap', '-p', '/sdcard/explore.png')
    $null = Invoke-Adb $Serial @('pull', '/sdcard/explore.png', $png)
    $null = Invoke-Adb $Serial @('shell', 'rm', '/sdcard/explore.png')
    Write-Output "screenshot: $png"
}
