<#
.SYNOPSIS  Bluetooth on/off. Values: on, off
  -Action get        prints the current value
  -Action set -Value <v>
#>
param([ValidateSet('get', 'set')][string]$Action = 'get', [string]$Value, [string]$Serial)
. "$PSScriptRoot\..\..\tools\common.ps1"
$Serial = Resolve-Serial $Serial
function Sh([string]$cmd) { (Invoke-Adb $Serial @('shell', $cmd)).Trim() }

if ($Action -eq 'get') {
    if ((Sh "settings get global bluetooth_on") -eq "0") { "off" } else { "on" }
    return
}
switch ($Value) { "on" { Sh "cmd bluetooth_manager enable" | Out-Null } "off" { Sh "cmd bluetooth_manager disable" | Out-Null } default { throw "bluetooth: use on|off" } }
# Wait until the radio reports the new state (no fixed sleep)
for ($i = 0; $i -lt 40; $i++) { $now = if ((Sh "settings get global bluetooth_on") -eq "0") { "off" } else { "on" }; if ($now -eq $Value) { return }; Start-Sleep -Milliseconds 250 }
throw "bluetooth did not turn $Value"
