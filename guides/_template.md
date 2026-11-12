# <App name> — UI guide
Version: <x.y.z> · Platform: android | windows · Verified: <yyyy-mm-dd> on <device/PC>
Package / AppUserModelId: <com.example.app | Name_hash!App>
Figma exports: guides/<app>/figma/<version>/

<!-- Pass 1 (from Figma): fill screens, labels and navigation; Status = unverified (selector = predicted text).
     Pass 2 (live app): run explore on each screen, fill the real Selector and set Status to one of:
       verified | differs (write "Figma: X / App: Y") | not found | not in Figma
     List every difference from the design under Quirks. Tests use only verified rows. -->

## Screens
### <Screen name>
Purpose: <what the user does here>
Reach from: <screen + control>
| Element | Label | Selector | Type | Status |
|---|---|---|---|---|
| <element> | "<visible label>" | <id: ... / role:Button && name:...> | <button/input/text/toggle> | unverified |

## Navigation map
- <Screen> → (<control>) → <Screen>

## Quirks
- <dialogs that may appear, slow loads, differences from Figma>

## Reusable flows
- <android/subflows/<app>/x.yaml | windows/subflows/<app>/x.yml> (inputs: ...)
