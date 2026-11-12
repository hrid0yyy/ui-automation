# UI test automation — user guide

How to install and use this system for every planned use case: Windows apps, Android phones, and tests that use
both at once. No MCP servers are involved; everything is plain PowerShell and Python scripts run from this folder.

- **GUIDE.md** (this file) — for people: what each part is for and how to use it.
- **AGENTS.md** — the rules an AI agent follows (Claude Code loads it through CLAUDE.md). Agents should read both.
- **guides/** — what we know about each app and each system screen, with verified selectors.

---

## 1. What the system does

| Part | Tool | What it drives |
|---|---|---|
| Android phone | Maestro CLI (pinned) + adb | Phone apps, via YAML "flows" |
| Windows PC | `tools/winrunner.py` on Python `uiautomation` | Windows apps, via YAML "workflows" |
| Both | `tools/run.ps1` | Runs any test, checks app version, applies settings, writes results |
| Exploring | `tools/explore-android.ps1`, `tools/explore-windows.ps1` | Prints the current screen as a list of elements + ready-to-use selectors |
| Knowledge | `guides/<app>/<platform>-<version>.md` | Screens, selectors, navigation, quirks per app version |

Every test run produces `results/<date>/<test id>/<time>/result.json` with each step's pass/fail, duration,
and, on failure, a screenshot and a dump of the screen.

---

## 2. Install on a new PC

Needs: Windows 10 1809+ or 11 (AMD64 or ARM64), internet, no admin rights.

1. Copy or clone this folder to a plain path (for example `C:\ui-automation`).
2. Double-click **`install.cmd`** (or run `powershell -ExecutionPolicy Bypass -File install.ps1`).

It installs, into `.tools\` only (nothing on the system PATH except Python, if it had to install Python):

| Item | Version | Source |
|---|---|---|
| Python (only if no 3.10+ is found) | `python_install` in `setup/versions.json` | python.org, per-user, signature checked |
| Microsoft OpenJDK | 17 | aka.ms (Microsoft) |
| Maestro CLI | `maestro` in `setup/versions.json` | GitHub release, SHA-256 checked |
| Python packages (venv) | uiautomation, comtypes, PyYAML (pinned) | PyPI |
| adb (platform-tools) | latest, only if no adb exists | Google |

Then it **checks** what cannot be installed from the PC and lists it as `[todo]`:
the apps under test (from `apps.json`), the phone's USB-debugging state, phone-brand settings, and the Maestro
driver on the phone. Fix the todos, then re-check:

```
powershell -ExecutionPolicy Bypass -File install.ps1 -CheckOnly
```

Other switches: `-Smoke` also runs one PC and one phone test; `-Force` reinstalls the toolchain.
Versions are pinned on purpose — change `setup/versions.json` only as its own change, then re-run all tests.

**ARM64 PCs:** the installer picks ARM64 builds of Python and the JDK. adb only exists for x64 and runs under
emulation. Run the smoke tests once on the ARM64 PC before trusting it.

---

## 3. Connect a phone (once per phone)

1. On the phone: Settings → About phone → tap the build number 7 times → Developer options → **USB debugging** on.
2. Connect by USB, unlock the phone, tap **Allow** on the "Allow USB debugging?" prompt.
3. Run `install.ps1 -CheckOnly`. It shows the brand, model, Android version and what is still missing.
4. Brand extras (see `guides/system/android/<brand>-<skin>.md`):
   - **Xiaomi / Redmi / POCO (HyperOS):** Developer options → **Install via USB** and
     **USB debugging (Security settings)** on (needs a Mi account). Without the second one, taps fail.
5. **Maestro driver:** the first phone test installs two helper apps. Watch the phone and tap **Install** on both
   prompts (Xiaomi cancels them after a few seconds otherwise).
6. **Cross-device tests:** copy `devices.example.json` to `devices.json` (git-ignored) and add the phone with its Quick Share name
   (Quick Share → "You'll appear as"):
   ```json
   { "<adb serial>": { "model": "Redmi Note 15 (2510DRA23G)", "quickShareName": "<Quick Share name>" } }
   ```
7. Keep the phone language fixed (the current guides assume English, UK). Text selectors depend on it.

A new phone brand needs a system guide: copy `guides/system/android/xiaomi-hyperos3.md` and fill in what differs.

---

## 4. Everyday commands

| Task | Command |
|---|---|
| Installed app versions (PC + phone) | `tools\run.ps1 -VersionOnly -App quick-share` |
| Run one test | `tools\run.ps1 -Test windows\workflows\quick-share\WTC-101-home-screen.yml` |
| Run a folder of tests | `tools\run.ps1 -Test android\flows\quick-share` |
| Check a test is stable | `tools\run.ps1 -Test <file> -Repeat 2` (must pass twice in a row) |
| Pick a phone when several are connected | add `-Serial <adb serial>` |
| Run a test outside its version range anyway | add `-IgnoreVersion` |
| What is on the phone screen now | `tools\explore-android.ps1` (add `-Screenshot` for a PNG) |
| Which windows are open | `tools\explore-windows.ps1` |
| What is in a window | `tools\explore-windows.ps1 -Window "Quick Share"` (add `-All`, `-Screenshot`) |
| Read/change a setting by hand | `android\settings\bluetooth.ps1 -Action get` / `-Action set -Value on` |

Run commands from the repo folder in PowerShell. If scripts are blocked, prefix with
`powershell -ExecutionPolicy Bypass -File`.

---

## 5. Use cases

### 5.1 Add a new app
1. Add it to **`apps.json`**:
   ```json
   "my-app": {
     "android": { "package": "com.example.myapp", "receiveDir": "/sdcard/Download/MyApp" },
     "windows": { "appx": "Vendor.MyApp", "aumid": "Vendor.MyApp_hash!App", "process": "myapp.exe" }
   }
   ```
   Find the Windows values with `Get-AppxPackage *myapp*` and `Get-StartApps *myapp*`; the Android package with
   `adb shell pm list packages | findstr myapp`. `receiveDir` is only needed for file-transfer tests.
   Desktop (non-Store) apps use `launch: {exe: "C:\\path\\app.exe"}` in workflows instead of an AUMID.
2. `tools\run.ps1 -VersionOnly -App my-app` must print a version on each platform.
3. Create `guides/my-app/android-<version>.md` and/or `windows-<version>.md` from `guides/_template.md`.

### 5.2 Figma design + version → app guide
Goal: a guide written from the design before (or alongside) testing the real app.

1. In Figma, export each screen (frame) as PNG or PDF, named after the screen (`home.png`, `settings.png`), into
   `guides/<app>/figma/<version>/`.
2. Ask the agent: *"Make the guide for <app> <version> from the Figma exports."* It creates
   `guides/<app>/<platform>-<version>.md` with every screen, element label, element type and the navigation
   between screens. Every row gets **Status = unverified** and a *predicted* text selector — Figma has no
   resource-ids or AutomationIds.
3. When the app is installed, ask: *"Verify the <app> guide against the real app."* The agent explores each
   screen (one action, then explore again) and sets each row to:
   - `verified` — found; selector replaced with the real one (id if the app has ids, else the real text)
   - `differs` — the app differs from the design; both are written down (e.g. "Figma: Send / App: Share")
   - `not found` — in the design, not in the app
   - `not in Figma` — in the app, not in the design (added anyway)
4. Only `verified` rows are used in tests.

For a new design version, the agent compares it with the previous guide and lists the changed screens; only those
screens and the tests that use them need rework.

### 5.3 Explore an app (by hand or by an agent)
- Always one action, then explore again. Never chain several blind actions.
- **Phone:** `tools\explore-android.ps1` (default Maestro source). Do **not** rely on `-Source adb` for dialogs and
  cards: the adb dump missed Quick Share's "Accept request?" card. To act: a one-step scratch Maestro flow, or
  `adb shell input ...` while exploring only.
- **PC:** `tools\explore-windows.ps1 -Window "<title>"`. To act, a one-step scratch workflow:
  ```
  .tools\venv\Scripts\python.exe tools\winrunner.py scratch.yml --out $env:TEMP\scratch
  ```
  Windows file dialogs (Open/Save) appear **inside** the app's window, not as their own window. Their controls have
  fixed ids that work in every language: File name box `id:1148`, Open/Save `id:1`, Cancel `id:2`.
- Record every new screen and selector in the app guide, with Status `verified`.

### 5.4 Write a phone test (Android)
File: `android/flows/<app>/TC-<n>-<slug>.yaml`
```yaml
appId: com.example.myapp
name: TC-201 Login screen shows
properties:
  testCaseId: "TC-201"
  app: "my-app"
  minVersion: "3.0"
  maxVersion: ""                 # "" = no upper limit
  settings: "wifi:on"            # name:value, comma-separated
tags: [smoke]
---
- launchApp
- extendedWaitUntil:
    visible: "Sign in"
    timeout: 15000
- tapOn: {id: "com.example.myapp:id/login"}
- assertVisible: "Welcome"
```
Selectors in this order: resource-id → visible text → never coordinates. Wait for elements; never fixed sleeps.
Apps with no launcher icon (like Quick Share inside Google Play services) use `launchIntent: "-a <action>"` in
`properties` instead of `launchApp`.

### 5.5 Write a PC test (Windows)
File: `windows/workflows/<app>/WTC-<n>-<slug>.yml`
```yaml
testCaseId: WTC-201
name: Settings page opens
app: my-app
minVersion: "3.0"
maxVersion: ""
tags: [smoke]
settings: [dark-mode:on]
window: "name:My App"                       # default scope for every selector
steps:
  - launch: {aumid: "Vendor.MyApp_hash!App", window: "name:My App"}
    timeout: 30
  - wait: "role:Button && name:Settings"
  - click: "role:Button && name:Settings"
  - assert: {selector: "role:CheckBox && id:AutoStart", toggled: false}
```
Selector syntax: `id:`, `name:` (exact), `name~:` (contains), `role:`, `class:`, `nth:`; join with `&&`; go deeper
with `>>` (e.g. `role:Group && name~:Run at startup >> role:CheckBox`). All actions are listed in AGENTS.md.

### 5.6 Cross-device test (PC acts, phone responds)
Example in the repo: `WTC-103-send-to-phone.yml` + `TC-103-receive-from-pc.yaml` (Quick Share PC → phone).

1. **Phone script** (`android/flows/<app>/TC-<n>-...yaml`): waits for the PC's action, then responds.
   In `properties`: `pairedFrom: "<path to the Windows workflow>"`. Start with a long wait
   (`extendedWaitUntil` ~90 s), because it starts before the PC acts.
2. **PC script** (`windows/workflows/<app>/WTC-<n>-...yml`): the one you run. Header:
   ```yaml
   pairedWith: ../../../android/flows/<app>/TC-<n>-....yaml
   fixture: tests/fixtures/<app>/<file>        # only for file transfers
   ```
   It can use `${PHONE_NAME}` (from `devices.json`), `${FIXTURE}` (absolute path of the fixture) and `${SERIAL}`.
3. Run `tools\run.ps1 -Test <the PC script> -Repeat 2`. It applies the settings of both scripts, opens the phone
   app, starts the phone script in the background, runs the PC script, waits for both, checks the received file on
   the phone matches the fixture (then deletes it), and restores all settings. One result.json holds the steps of
   both devices (`pc:` / `phone:` prefixes).

Each half can still run on its own (useful while building it): run the phone file with `run.ps1`, and send from the
PC by hand or with `winrunner.py --env FIXTURE=... --env PHONE_NAME=...`.

### 5.7 Preconditions (settings)
List them in the test header; `run.ps1` sets them before the test and restores the old values afterwards.

| Phone (`android/settings/`) | PC (`windows/settings/`) |
|---|---|
| wifi, bluetooth, dark-mode, location, airplane-mode, font-scale | bluetooth, dark-mode |

New setting: copy an existing script and keep the same interface
(`-Action get` prints the value; `-Action set -Value <v>` changes it). Use the Settings UI only if no command works.

### 5.8 A new app version arrives
1. `tools\run.ps1 -VersionOnly -App <app>` shows the new version.
2. Run all tests for the app. Tests whose `minVersion`/`maxVersion` exclude it are logged as skipped.
3. For screens that changed, copy the guide to `<platform>-<new version>.md`, re-explore the changed screens and
   update selectors. Old tests keep working for the old version through their version range.

### 5.9 A test fails
Open `results/<date>/<test id>/<time>/`:
- `result.json` — the failing step and its error message
- PC: `step<N>.png` (screen) and `step<N>.txt` (the window's element tree at that moment), `runner-console.txt`
- Phone: `maestro-console.txt`, `maestro-debug/` (screenshots), `junit.xml`; for paired tests under `phone\`

| Error looks like | Usually means | Do this |
|---|---|---|
| `Element not found` / `Assert that ... is visible` failed | Label or screen changed, or wrong language | Explore that screen, fix the selector in test + guide |
| Passes sometimes | Waiting too short | Raise that step's `timeout`; never add sleeps |
| `INSTALL_FAILED_USER_RESTRICTED`, "Device server died" | Phone cancelled the Maestro driver install | Re-run while watching the phone; tap Install |
| `INJECT_EVENTS` SecurityException | Xiaomi "USB debugging (Security settings)" off | Turn it on |
| `No Android device connected` / `unauthorized` | USB / authorisation | Reconnect, unlock, tap Allow |
| Cross-device: PC shows "Failed" | Phone did not accept in time (~1 min) | Check the phone script reached the accept step |
| `skipped` | App version outside the test's range, or app missing | Expected; or use `-IgnoreVersion` to try anyway |

### 5.10 Working with an AI agent
Open this folder in Claude Code (or another agent that reads AGENTS.md) and ask in plain words:
- *"Check the system is ready."* → runs `install.ps1 -CheckOnly`, reports todos.
- *"Here is the Figma for <app> <version> in guides/<app>/figma/<version>; make the guide."* → section 5.2.
- *"Write a test: <steps and expected result>, on the phone / PC / both."* → explores, writes the script(s),
  runs them twice, updates the guide, reports the result.json paths.
- *"Run all Quick Share tests and tell me what failed."*

The agent must explore before writing selectors, run every new test twice, update the guide, and stop and ask you
when something needs a person (phone prompts, accounts, a test direction the system cannot do yet).

---

## 6. Limits today
- Cross-device tests are **PC-led only**: the PC acts, the phone responds. Phone → PC is not supported yet, and
  received files are checked on the phone only.
- One PC + one phone per test; one hand-off between them (no back-and-forth sync points).
- Apps without ids (Quick Share) need text selectors, so device languages must stay fixed.
- Figma import is from exported images/PDFs; there is no Figma API exporter.
- Verified on AMD64 Windows 11 + Redmi Note 15 (HyperOS 3, Android 16). Not yet run on an ARM64 PC.

---

## 7. Folder map
```
install.cmd / install.ps1     new-PC installer + readiness check
AGENTS.md                     rules for AI agents (CLAUDE.md points here)
GUIDE.md                      this guide
apps.json                     apps under test: package / AUMID / process / receiveDir
devices.json                  per-phone facts adb cannot read (local only; template: devices.example.json)
setup/                        setup.ps1 (toolchain) + versions.json (pins)
tools/                        run.ps1, explore-*.ps1, winrunner.py, wincore.py, testmeta.py, androidtree.py, common.ps1
android/flows/<app>/          phone tests (TC-*.yaml)
android/subflows/             reusable phone steps (+ system/<brand>/ for brand popups)
android/settings/             phone setting scripts (get/set)
windows/workflows/<app>/      PC tests (WTC-*.yml)
windows/subflows/<app>/       reusable PC steps
windows/settings/             PC setting scripts (get/set)
tests/fixtures/<app>/         files used by tests (e.g. files to send)
guides/<app>/                 app guides per platform + version, figma/<version>/ exports
guides/system/                phone-brand and Windows system guides
results/                      test results (not in git)
.tools/                       installed toolchain (not in git)
```
