<#
.SYNOPSIS  Font size multiplier. Values: e.g. 0.85, 1.0, 1.15, 1.3
  -Action get        prints the current value
  -Action set -Value <v>
#>
param([ValidateSet('get', 'set')][string]$Action = 'get', [string]$Value, [string]$Serial)
. "$PSScriptRoot\..\..\tools\common.ps1"
$Serial = Resolve-Serial $Serial
function Sh([string]$cmd) { (Invoke-Adb $Serial @('shell', $cmd)).Trim() }

if ($Action -eq 'get') {
    $v = Sh "settings get system font_scale"; if ($v -eq "null" -or -not $v) { "1.0" } else { $v }
    return
}
if (-not ($Value -as [double])) { throw "font-scale: use a number like 1.15" }
Sh "settings put system font_scale $Value" | Out-Null
