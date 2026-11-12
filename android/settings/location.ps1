<#
.SYNOPSIS  Location services. Values: on, off
  -Action get        prints the current value
  -Action set -Value <v>
#>
param([ValidateSet('get', 'set')][string]$Action = 'get', [string]$Value, [string]$Serial)
. "$PSScriptRoot\..\..\tools\common.ps1"
$Serial = Resolve-Serial $Serial
function Sh([string]$cmd) { (Invoke-Adb $Serial @('shell', $cmd)).Trim() }

if ($Action -eq 'get') {
    if ((Sh "cmd location is-location-enabled") -match "true") { "on" } else { "off" }
    return
}
switch ($Value) { "on" { Sh "cmd location set-location-enabled true" | Out-Null } "off" { Sh "cmd location set-location-enabled false" | Out-Null } default { throw "location: use on|off" } }
