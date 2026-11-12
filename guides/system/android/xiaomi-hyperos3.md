# Xiaomi / Redmi / POCO — HyperOS 3 system guide
Verified: 2026-11-12 on Redmi Note 15 (model 2510DRA23G, codename spinel), HyperOS OS3.0.303.0.WPGMIXM, Android 16, en-GB
BRAND passed to Maestro: `xiaomi` (from ro.product.manufacturer; covers Redmi and POCO)

## Onboarding checklist (this phone)
- [x] Developer options on (`settings get global development_settings_enabled` = 1)
- [x] USB debugging on (`adb devices` shows the phone)
- [x] Install via USB on (`persist.security.adbinstall` = 1; Maestro installs its driver APKs)
- [x] **USB debugging (Security settings)** — ON since 2026-11-12 (`persist.security.adbinput` = 1). Without it `input tap/keyevent` and Maestro taps fail with
      `SecurityException: ... INJECT_EVENTS`. Turn it on by hand: Settings → Additional settings → Developer options →
      "USB debugging (Security settings)". Xiaomi asks for a Mi account sign-in (and sometimes a SIM) to enable it.
- [x] **Maestro driver installed** (2026-11-12). Maestro installs two helper apps (`dev.mobile.maestro`, `dev.mobile.maestro.test`).
      HyperOS shows an "Install via USB" confirmation for each; if nobody taps Install within a few seconds the install is
      cancelled (`INSTALL_FAILED_USER_RESTRICTED`) and the run fails. Run any test once while watching the phone and tap
      Install on both prompts. run.ps1 and explore-android.ps1 pass `--no-reinstall-driver`, so after that the prompts
      should not come back.
- [x] Smoke tests pass: `tools\run.ps1 -Test android\flows\quick-share -Repeat 2` — TC-101 and TC-102 passed twice
      (2026-11-12, results\2026-11-12\TC-101\232156, results\2026-11-12\TC-102\232221)
- [ ] Brand subflows for system popups (android/subflows/system/xiaomi/)

## Settings app (com.android.settings/.MiuiSettings)
Open: `adb shell am start -a android.settings.SETTINGS`
Rows use `android:id/title` (shared id) — select with `{id: "android:id/title", text: "<row>"}`.
Top-level rows seen: About phone, System apps updater, Security status, Wi-Fi, Bluetooth, Mobile networks,
Interconnectivity, Portable hotspot, VPN, More connectivity options, Lock screen, ...
Right-side value: `com.android.settings:id/text_right` (e.g. Bluetooth "Off").
Search box: `id: android:id/input` ("Search settings").

## Command routes that work here (no root)
| Setting | Command |
|---|---|
| Wi-Fi | `cmd wifi set-wifi-enabled enabled|disabled` |
| Bluetooth | `cmd bluetooth_manager enable|disable` |
| Dark mode | `cmd uimode night yes|no` |
| Location | `cmd location set-location-enabled true|false` |
| Airplane mode | `cmd connectivity airplane-mode enable|disable` |
| Font scale | `settings put system font_scale <n>` |

## Keyboard
Default IME: Gboard (`com.google.android.inputmethod.latin`). Prefer `inputText` on a focused field.

## Known system popups (add subflows as they are met)
- Autostart / battery saver prompts for third-party apps — not yet seen
- "USB debugging (Security settings)" warning dialog when enabling — manual, one time
