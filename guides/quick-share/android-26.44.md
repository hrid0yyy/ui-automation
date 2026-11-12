# Quick Share (Android) — UI guide
Version: Google Play services 26.44.31 · Platform: android · Verified: 2026-11-12 on Redmi Note 15 (2510DRA23G), HyperOS 3.0, Android 16, en-GB
Package: com.google.android.gms (Quick Share has no launcher activity of its own)
Figma exports: guides/quick-share/figma/26.44/ (none yet)

Open it with an intent (the runner or a scratch command, not inside a Maestro flow):
`adb -s <serial> shell am start -a com.google.android.gms.nearby.QUICK_SHARE`
Activity: `com.google.android.gms/.nearby.sharing.main.MainActivity`

The UI is Jetpack Compose: **no resource-ids**. Selectors are visible text / content-desc,
so they depend on the phone language (keep the phone on en-GB).

## Screens
### Main — Receive tab
Purpose: make the phone visible and see incoming shares
Reach from: QUICK_SHARE intent (opens on Receive)
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Title | "Quick Share" | text: Quick Share | text | verified |
| Back | (icon) | text: Back (content-desc) | button | verified |
| Help | (icon) | text: Help (content-desc) | button | verified |
| More menu | (icon) | text: More (content-desc) | button | verified |
| Identity label | "You'll appear as" | text: You'll appear as | text | verified |
| Device name | "<device name>" | text: <device name> | text | verified |
| Visibility | "Temporarily visible to everyone" | text: Temporarily visible to everyone | text | verified |
| Section | "Sharing with you" | text: Sharing with you | text | verified |
| Bluetooth prompt (only when Bluetooth is off) | "Turn on Bluetooth" | text: Turn on Bluetooth | button | verified (visible), tap not verified |
| Receive tab | "Receive" | text: Receive | tab | verified |
| Send tab | "Send" | text: Send | tab | verified (visible), tap not verified |

### Settings
Purpose: account, device name, visibility, mobile data
Reach from: Main → (More) → Settings (not yet verified by tap; same activity)
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Account row | "Account" | text: Account | row | verified |
| Device name row | "Device name" | text: Device name | row | verified |
| Visibility row | "Who can share with you" | text: Who can share with you | row | verified |
| Visibility value | "Anyone nearby" | text: Anyone nearby | text | verified |
| Mobile data | "Use mobile data" | text: Use mobile data | toggle row | verified |

### Main — idle, ready to receive (Bluetooth on)
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Status | "Ready to receive" | text: Ready to receive | text | verified |
| Recent files | "Recent files" | text: Recent files | text | verified |
| Downloads row | "Quick Share downloads" / "Find recent downloads" | text: Quick Share downloads | row | verified |

### Incoming request card (under "Sharing with you")
Reach from: another device sends to this phone while Main is open
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Sender | "<sender device name>" | text: <sender device name> | text | verified |
| Prompt | "Accept request?" | text: Accept request? | text | verified |
| Size | "1 file (115 B)" | text: 1 file (115 B) | text | verified |
| PIN | "PIN: nnnn" (same as on the sender) | text: PIN: .* (regex) | text | verified |
| Decline | "Decline" | text: Decline | button | verified (visible), tap not verified |
| Accept | "Accept" | text: Accept | button | verified (tapOn) |

### Received card (after Accept)
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Status | "Received" | text: Received | text | verified |
| View downloads | "View downloads" | text: View downloads | button | verified (visible) |
| Open | "Open" | text: Open | button | verified (visible) |

Received files land in `/sdcard/Download/Quick Share/<file name>`. Accept within about a minute or the sender shows
"Failed". `explore-android.ps1 -Source adb` (uiautomator dump) does NOT show the request card; use the default
Maestro source.

## Navigation map
- QUICK_SHARE intent → Main (Receive tab)
- Main + incoming share → request card → (Accept) → Received card (verified 2026-11-12, from the PC)
- Main → (Send) → Send tab — unverified
- Main → (More) → Settings — unverified

## Quirks
- Taps need Xiaomi "USB debugging (Security settings)" on; see guides/system/android/xiaomi-hyperos3.md.
- The intent brings an existing task to the front instead of a fresh screen; use `stopApp`/`clearState` with care
  (it is Google Play services, so `pm clear` is not allowed — it would wipe GMS).
- "Turn on Bluetooth" appears instead of the device list when Bluetooth is off; tests set `bluetooth:on`.

## Reusable flows
- android/subflows/quick-share/assert-main.yaml — Main screen is showing
- android/flows/quick-share/TC-103-receive-from-pc.yaml — accept an incoming file (receiver half of WTC-103)
