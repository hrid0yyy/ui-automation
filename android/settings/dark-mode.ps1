<#
.SYNOPSIS  System dark theme. Values: on, off
  -Action get        prints the current value
  -Action set -Value <v>
#>
param([ValidateSet('get', 'set')][string]$Action = 'get', [string]$Value, [string]$Serial)
. "$PSScriptRoot\..\..\tools\common.ps1"
$Serial = Resolve-Serial $Serial
function Sh([string]$cmd) { (Invoke-Adb $Serial @('shell', $cmd)).Trim() }

if ($Action -eq 'get') {
    if ((Sh "cmd uimode night") -match "yes") { "on" } else { "off" }
    return
}
switch ($Value) { "on" { Sh "cmd uimode night yes" | Out-Null } "off" { Sh "cmd uimode night no" | Out-Null } default { throw "dark-mode: use on|off" } }
