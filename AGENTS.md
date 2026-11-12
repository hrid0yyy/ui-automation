# UI test automation — agent rules

Android phones are driven by the Maestro CLI; Windows apps by `tools/winrunner.py` (Python `uiautomation`).
No MCP servers are used. Everything below is a plain command run from the repo root in PowerShell.

GUIDE.md explains every use case end to end (install, phones, new apps, Figma → guide, single and cross-device
tests, failures). Read it once; this file holds the rules.

## First time on a PC
- `powershell -ExecutionPolicy Bypass -File install.ps1` installs everything (Python if missing, then `setup\setup.ps1`: pinned JDK, Maestro, Python packages, adb into `.tools\`) and checks apps and phones. `install.ps1 -CheckOnly` re-checks; report its `[todo]` items to the user — they need a person.
- Pinned versions live in `setup/versions.json`. Do not upgrade them as part of a test change.

## Before anything
- Check the installed app version: `tools\run.ps1 -VersionOnly -App <app>` (apps are listed in `apps.json`).
- Read `guides/<app>/<platform>-<version>.md` for the closest version; if none exists, start one from `guides/_template.md`.
- For system screens read `guides/system/android/<brand>-<skin>.md` or `guides/system/windows/settings.md`.

## Figma → guide
- Exports live in `guides/<app>/figma/<version>/` (PNG/PDF, one per screen). Write `guides/<app>/<platform>-<version>.md`
  from `guides/_template.md`: every screen, label, type, navigation; Status `unverified`, selector = predicted text.
- Against the live app, set each row to `verified` (real selector), `differs` (write both), `not found`, or `not in Figma`.
- Only `verified` rows may be used in tests.

## Exploring
- Android: `tools\explore-android.ps1 [-Serial <s>] [-Source adb] [-Screenshot]`
- Windows: `tools\explore-windows.ps1` lists windows; `tools\explore-windows.ps1 -Window "<name>" [-All] [-Screenshot]`
- To act while exploring, use one command, then explore again. Never chain blind actions.
- Android dialogs/cards: use the default Maestro source; `-Source adb` missed Quick Share's request card.
- Windows file dialogs are children of the app window (scope `role:Window && name:Open >> ...`); use their fixed ids
  (File name `id:1148`, Open/Save `id:1`, Cancel `id:2`).
  - Android: `adb -s <s> shell input tap|text|keyevent ...` (exploring only, never in test cases), or a scratch Maestro flow.
  - Windows: a scratch workflow with one step: `.tools\venv\Scripts\python.exe tools\winrunner.py scratch.yml --out $env:TEMP\scratch`.

## Selectors (in this order)
1. Android resource-id (`id:`) / Windows AutomationId (`id:`)
2. Visible text / Name, plus `role:` on Windows (`role:Button && name:Send`)
3. Never coordinates, never index-only selectors. `nth:` only together with other parts.

## Waiting
- Wait for elements, never fixed sleeps. Android: `extendedWaitUntil`, `assertVisible` (built-in wait). Windows: `wait`, `timeout:` per step.
- The Windows `pause` action exists only for runner self-tests; do not use it in test cases.

## Settings
- Use scripts in `android/settings/` or `windows/settings/` (each supports `-Action get` and `-Action set -Value <v>`).
- List them in the test header as `name:value`; `run.ps1` applies them, runs the test, then restores the previous value.
- Use the Settings UI only if no script can do it; then write a new settings script with the same get/set interface.

## Writing test cases
- One test case per file. Android: `android/flows/<app>/TC-<n>-<slug>.yaml`. Windows: `windows/workflows/<app>/WTC-<n>-<slug>.yml`.
- Required header fields: testCaseId, app (key in `apps.json`), minVersion, maxVersion ("" = open), tags, settings.
- Reuse subflows; extract any step sequence used twice into a subflow. Brand system dialogs go in `android/subflows/system/<brand>/`.
- `${BRAND}` (e.g. `xiaomi`) and `${SERIAL}` are passed to every Android flow.

Android header (Maestro):
```yaml
appId: com.google.android.gms
name: TC-101 Quick Share receive screen opens
properties:
  testCaseId: "TC-101"
  app: "quick-share"
  minVersion: "26.0"
  maxVersion: ""
  settings: "bluetooth:on,wifi:on"     # comma-separated name:value
  launchIntent: "-a com.google.android.gms.nearby.QUICK_SHARE"   # optional: run.ps1 opens it (fresh task) before the flow
tags:
  - smoke
---
- runFlow: ../../subflows/quick-share/assert-main.yaml
```
Use `launchApp` for normal apps; use `launchIntent` only for apps with no launcher icon (Maestro flows cannot run adb).

Windows header and steps:
```yaml
testCaseId: WTC-101
name: Quick Share window opens
app: quick-share
minVersion: "1.0"
maxVersion: ""
tags: [smoke]
settings: [bluetooth:on]
window: "name:Quick Share"          # default scope for every selector
steps:
  - id: start
    launch: {aumid: "NearbyShare_21hpf16v5xp10!NearbyShare"}
    timeout: 30
  - wait: "role:Button && name~:Select"
  - click: "role:Button && name~:Select"
```

Windows actions (one per step; optional step keys: `id`, `timeout` seconds (default 10), `optional: true`, `window`, `description`):

| Action | Argument |
| --- | --- |
| `launch` | `{aumid: ...}` or `{exe: ..., args: [...]}`; optional `window:` to set the scope |
| `close` | process name, e.g. `nearby_share.exe` |
| `window` | selector or Name substring of a top-level window; becomes the scope |
| `click` / `double_click` / `right_click` / `invoke` | selector |
| `type` | `{selector: ..., text: ..., clear: true}` |
| `key` | uiautomation keys, e.g. `"{Ctrl}a"`, `"{Esc}"`, `"{Enter}"` |
| `wait` / `wait_gone` | selector |
| `assert` | selector, or `{selector, name, value, enabled, toggled}` |
| `assert_not` | selector (must be absent now) |
| `toggle` | `{selector: ..., on: true}` |
| `select` / `scroll_into_view` | selector |
| `screenshot` | file name without extension |
| `run_flow` | path relative to this file, or `{path: ..., env: {KEY: value}}` |

Strings may use `${VAR}`; values come from the workflow's `env:` map or `--env KEY=VALUE`.

## Cross-device tests (PC + phone): `pairedWith`
One script per device; the Windows workflow is the one you run.
- Windows workflow header: `pairedWith: <path to the Android flow, relative to this file>` and, for transfers,
  `fixture: <repo-relative file>` (fixtures live in `tests/fixtures/<app>/`).
- Android flow properties: `pairedFrom: "<path to the Windows workflow>"`. Folder runs skip it; running the file
  directly still works (it waits for something to arrive).
- `tools\run.ps1 -Test <the Windows workflow>` then: applies the settings of both scripts → runs the phone flow's
  `launchIntent` → starts the phone flow in the background → runs the PC workflow → waits for both (3 min hard stop)
  → if `fixture:` is set, checks the file is in `apps.json` `<app>.android.receiveDir` with the same content (line
  endings ignored) and deletes it → resets settings. One `result.json` (platform `windows+android`) holds the steps
  of both devices; phone steps are prefixed `phone:`, PC steps `pc:`; the phone's Maestro files are in `phone\`.
- Variables passed to the PC workflow: `FIXTURE` (absolute path), `PHONE_NAME` (the phone's Quick Share name from
  `devices.json` by serial, else Settings > Global > device_name), `SERIAL`.
- The phone flow must wait for the PC (e.g. `extendedWaitUntil` 90 s), because it starts first.
- `pairedWith` goes on the Windows workflow only; the reverse direction (phone sends to PC) is not supported yet.
- Example: `windows/workflows/quick-share/WTC-103-send-to-phone.yml` + `android/flows/quick-share/TC-103-receive-from-pc.yaml`.

## Running
- `tools\run.ps1 -Test <file-or-folder> [-Serial <s>] [-Repeat 2]`
- Results: `results/<date>/<test_id>/<time>/result.json` (+ screenshots, tree dumps, Maestro logs).
- Tests outside minVersion–maxVersion are skipped and logged as skipped.

## Done means
- Passes twice in a row: `tools\run.ps1 -Test <file> -Repeat 2`.
- Guide updated with new screens and verified selectors.
- Result JSON path mentioned in the change.
