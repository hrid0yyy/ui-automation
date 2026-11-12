<#
.SYNOPSIS  Airplane mode. Values: on, off
  -Action get        prints the current value
  -Action set -Value <v>
#>
param([ValidateSet('get', 'set')][string]$Action = 'get', [string]$Value, [string]$Serial)
. "$PSScriptRoot\..\..\tools\common.ps1"
$Serial = Resolve-Serial $Serial
function Sh([string]$cmd) { (Invoke-Adb $Serial @('shell', $cmd)).Trim() }

if ($Action -eq 'get') {
    if ((Sh "settings get global airplane_mode_on") -eq "1") { "on" } else { "off" }
    return
}
switch ($Value) { "on" { Sh "cmd connectivity airplane-mode enable" | Out-Null } "off" { Sh "cmd connectivity airplane-mode disable" | Out-Null } default { throw "airplane-mode: use on|off" } }
