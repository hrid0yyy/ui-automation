<#
.SYNOPSIS  Wi-Fi on/off. Values: on, off
  -Action get        prints the current value
  -Action set -Value <v>
#>
param([ValidateSet('get', 'set')][string]$Action = 'get', [string]$Value, [string]$Serial)
. "$PSScriptRoot\..\..\tools\common.ps1"
$Serial = Resolve-Serial $Serial
function Sh([string]$cmd) { (Invoke-Adb $Serial @('shell', $cmd)).Trim() }

if ($Action -eq 'get') {
    if ((Sh "settings get global wifi_on") -eq "0") { "off" } else { "on" }
    return
}
switch ($Value) { "on" { Sh "cmd wifi set-wifi-enabled enabled" | Out-Null } "off" { Sh "cmd wifi set-wifi-enabled disabled" | Out-Null } default { throw "wifi: use on|off" } }
