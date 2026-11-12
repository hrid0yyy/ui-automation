# Windows system settings guide
Verified: 2026-11-12 on AMD64, Windows build 26200, en-US

## Command routes (windows/settings/*.ps1, each with -Action get | set -Value <v>)
| Script | Values | How |
|---|---|---|
| bluetooth.ps1 | on, off | Windows.Devices.Radios WinRT API (no admin); runs under Windows PowerShell 5.1 |
| dark-mode.ps1 | on, off | HKCU ...\Themes\Personalize AppsUseLightTheme + SystemUsesLightTheme, then broadcasts ImmersiveColorSet |

## Opening Settings pages (UI route, only when no command exists)
`Start-Process ms-settings:bluetooth`, `ms-settings:display`, `ms-settings:colors`, `ms-settings:network-wifi`, ...
Then drive the Settings window with a workflow (`window: "name:Settings"`) and record selectors here.

## Not possible
- Anything blocked by policy or needing a reboot mid-test.
