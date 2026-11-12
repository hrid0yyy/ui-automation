# Quick Share (Windows) — UI guide
Version: 1.0.2757.0 · Platform: windows · Verified: 2026-11-12 on AMD64 PC, Windows build 26200, en-US
AppUserModelId: NearbyShare_21hpf16v5xp10!NearbyShare · Appx name: NearbyShare · Process: nearby_share.exe
Figma exports: guides/quick-share/figma/1.0.2757/ (none yet)

The UI is Flutter (window class `Google.Windows.NearbyShare`, one `FLUTTERVIEW` pane). There are **no AutomationIds**;
selectors are role + Name, so they depend on the Windows display language. Flutter builds its UI Automation tree only
after the first query — explore-windows.ps1 retries once, and runner steps wait up to their timeout.

## Screens
### Home
Purpose: pick files to send; shows who can see this PC
Reach from: launch (AUMID above)
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Device name | "<PC name>" | role:Group && name:<PC name> | group | verified |
| Visibility | "Everyone" | role:Button && name:Everyone | button | verified |
| Support | "Support" | role:Button && name:Support | button | verified |
| Settings | "Settings" | role:Button && name:Settings | button | verified |
| Account | "Signed in as <name> <email>" | role:Button && name~:Signed in as | button | verified |
| Drop zone | "Drop files or folders to send" | role:Text && name:Drop files or folders to send | text | verified |
| Select | "Select" | role:Button && name:Select | button | verified |

### Settings
Purpose: device name, visibility, download folder, startup, diagnostics
Reach from: Home → (Settings)
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Back | "Back" | role:Button && name:Back | button | verified |
| Title | "Settings" | role:Group && name:Settings | group | verified |
| Device name | "Device name\n<PC name>" | role:Text && name~:Device name | text | verified |
| Visibility | "Device visibility\nAnyone nearby can share with you" | role:Text && name~:Device visibility | text | verified |
| Download folder | "Save received files to\n<path>" | role:Text && name~:Save received files to | text | verified |
| Start at login toggle | (unnamed) | role:Group && name~:Run automatically at startup >> role:CheckBox | toggle | verified (read) |
| Diagnostics toggle | (unnamed) | role:Group && name~:Send usage & diagnostics data >> role:CheckBox | toggle | verified (read) |
| Version | "About Quick Share\nVersion 1.0.2757.0" | role:Text && name~:About Quick Share | text | verified |

### Select menu and file picker
Reach from: Home → (Select)
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Files | "Files" | role:Button && name:Files | button | verified |
| Folders | "Folders" | role:Button && name:Folders | button | verified |
| Open dialog | "Open" (child of the Quick Share window, not a top-level window) | role:Window && name:Open | window | verified |
| File name box | "File name:" (Win32 control id 1148, language-independent) | role:Window && name:Open >> role:Edit && id:1148 | input | verified (type + value) |
| Open button | "Open" (Win32 control id 1) | role:Window && name:Open >> role:SplitButton && id:1 | button | verified (invoke) |
| Cancel | "Cancel" (id 2) | role:Window && name:Open >> role:Button && id:2 | button | seen |

### Send (after a file is picked)
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| Selection | "Selected files\nSharing 1 file" | role:Group && name~:Selected files | group | verified |
| Clear / Add | "Clear", "Add" | role:Button && name:Clear / name:Add | button | verified |
| Searching | "Looking for nearby devices…" | role:Text && name~:Looking for nearby devices | text | verified |
| Device group | "Other devices" | role:Group && name:Other devices | group | verified |
| Target device | "Share <device> Phone" | role:Button && name~:<device name> | button | verified (click) |
| Sending | "Cancel <device> Connecting…" → "Cancel <device> PIN: nnnn Waiting…" | role:Button && name~:Cancel | button | verified |
| Done | "<device> Sent" (disabled) / "<device> Failed" | role:Group && name:Other devices >> role:Button && name~:Sent | button | verified |

## Navigation map
- Launch → Home
- Home → (Settings) → Settings → (Back) → Home
- Home → (Select) → Files → Open dialog → device list → (device) → Sent (verified 2026-11-12, PC → Redmi Note 15)
- Home → (Everyone) → visibility options — unverified

## Quirks
- Names of multi-line rows contain a line break; match with `name~:` on the first line.
- Toggles have no Name; scope them under their row Group with `>>`.
- Closing the window keeps the app in the tray; tests stop `nearby_share.exe` first (subflow open-home.yml).

## Reusable flows
- windows/subflows/quick-share/open-home.yml — fresh start, waits for Home
- windows/workflows/quick-share/WTC-103-send-to-phone.yml — full PC → phone send (paired with TC-103)
