<#
.SYNOPSIS
  Print a Windows app window as a compact element list (one line per element).

.EXAMPLE
  tools\explore-windows.ps1                          # list top-level windows
  tools\explore-windows.ps1 -Window "Quick Share"    # Name substring
  tools\explore-windows.ps1 -Window "Quick Share" -All -Screenshot
#>
param(
    [string]$Window,
    [switch]$All,
    [int]$Depth = 40,
    [switch]$Screenshot
)

. "$PSScriptRoot\common.ps1"
$py = Get-ToolPath 'python'
if (-not (Test-Path $py)) { throw 'Python venv missing. Run setup\setup.ps1 first.' }
$pyArgs = @("$PSScriptRoot\winexplore.py", '--depth', $Depth)
if ($Window) { $pyArgs += @('--window', $Window) }
if ($All) { $pyArgs += '--all' }
if ($Screenshot) {
    $png = Join-Path ([IO.Path]::GetTempPath()) 'explore-windows.png'
    $pyArgs += @('--screenshot', $png)
}
$env:PYTHONIOENCODING = 'utf-8'
& $py @pyArgs
exit $LASTEXITCODE
