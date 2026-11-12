<#
.SYNOPSIS  Bluetooth radio on/off (Windows.Devices.Radios, no admin needed). Values: on, off
  -Action get        prints the current value
  -Action set -Value <v>
  Must run in Windows PowerShell 5.1 (WinRT projection); run.ps1 does that.
#>
param([ValidateSet('get', 'set')][string]$Action = 'get', [string]$Value)
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Action', $Action)
    if ($Value) { $a += @('-Value', $Value) }
    & powershell.exe @a
    exit $LASTEXITCODE
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Await($op, [Type]$type) {
    $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
    $t.Result
}
[void][Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime]
[void][Windows.Devices.Radios.RadioAccessStatus, Windows.System.Devices, ContentType = WindowsRuntime]
[void][Windows.Devices.Radios.RadioState, Windows.System.Devices, ContentType = WindowsRuntime]

$radios = Await ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
$bt = $radios | Where-Object { $_.Kind -eq 'Bluetooth' } | Select-Object -First 1
if (-not $bt) { throw 'No Bluetooth radio found' }

if ($Action -eq 'get') {
    if ($bt.State -eq 'On') { 'on' } else { 'off' }
    return
}
$want = switch ($Value) { 'on' { 'On' } 'off' { 'Off' } default { throw 'bluetooth: use on|off' } }
$access = Await ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
if ("$access" -ne 'Allowed') { throw "Radio access: $access" }
$res = Await ($bt.SetStateAsync($want)) ([Windows.Devices.Radios.RadioAccessStatus])
if ("$res" -ne 'Allowed') { throw "SetState returned $res" }
