<#
.SYNOPSIS  Windows app + system dark theme. Values: on, off
  -Action get        prints the current value
  -Action set -Value <v>
#>
param([ValidateSet('get', 'set')][string]$Action = 'get', [string]$Value)
$ErrorActionPreference = 'Stop'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

if ($Action -eq 'get') {
    $light = (Get-ItemProperty $key -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
    if ($light -eq 0) { 'on' } else { 'off' }
    return
}
switch ($Value) {
    'on' { $light = 0 }
    'off' { $light = 1 }
    default { throw 'dark-mode: use on|off' }
}
Set-ItemProperty $key -Name AppsUseLightTheme -Value $light -Type DWord
Set-ItemProperty $key -Name SystemUsesLightTheme -Value $light -Type DWord
# Tell running apps the theme changed (WM_SETTINGCHANGE "ImmersiveColorSet")
Add-Type -Namespace Win32 -Name Msg -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint flags, uint timeout, out System.UIntPtr result);
'@ -ErrorAction SilentlyContinue
$r = [UIntPtr]::Zero
[void][Win32.Msg]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$r)
