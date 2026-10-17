# MouseForge

A native macOS menu-bar app for customizing any mouse, with deep support
for Logitech mice over HID++ 2.0:
- button remapping with click, double-click, triple-click, hold, modifier, and gesture triggers;
- a radial Actions Ring;
- Smart Action macros;
- smooth scrolling;
- pointer control;
- per-app profiles.

All code, UI, icons, and mouse illustrations are original.

## Build and run

Requirements: macOS 13+, Xcode 16+ (project uses synchronized folders).

```sh
xcodebuild -project MouseForge.xcodeproj -scheme MouseForge -allowProvisioningUpdates build
xcodebuild -project MouseForge.xcodeproj -scheme MouseForge -allowProvisioningUpdates test
```

You can also open `MouseForge.xcodeproj` and press ⌘R (run) or ⌘U (tests).
Signing is automatic with a team; see [docs/SIGNING.md](docs/SIGNING.md) for
why that matters for permissions.

## Permissions

| Permission | Why | Required |
|---|---|---|
| Accessibility | Active event tap (see and change clicks, scrolling, keys), window actions, Notification Center | Yes |
| Input Monitoring | Opening Logitech HID++ interfaces (battery, DPI, SmartShift, gesture button, thumb wheel, haptics) | For Logitech features |
| Automation (asked on first use) | AppleScript actions that control other apps | Only if used |
| Notifications (asked on first low battery) | Low-battery alerts | Optional |

Checks never prompt. The prompts only appear when you click "Grant Access…"
during onboarding. Permission changes are picked up live, and onboarding
offers "Relaunch MouseForge" when macOS needs a restart to apply one.

## Safety

- Left and right click are never remapped unless you unlock them
  (General ▸ Safety).
- **⌃⌥⌘M** turns all remapping off or on instantly, from any app. It's handled
  inside the event tap itself, so it works even if the UI is busy.
- Logitech controls are diverted only while they have an action, and are
  handed back when MouseForge quits.
- Custom pointer settings are undone when you switch back to "System" or
  quit.

## Architecture

| Module | Files |
|---|---|
| EventTapEngine | `Engine/EventTapEngine.swift`: tap on its own high-priority thread, never blocks |
| TriggerDetector | `Engine/TriggerDetector.swift`: click/double/triple/hold/gesture state machine, timers on the tap thread |
| GestureRecognizer | `Engine/GestureRecognizer.swift` |
| ActionLibrary / ActionExecutor | `Actions/`: protocol-based actions, run on a background queue |
| ProfileManager / AppWatcher | `Profiles/`: frontmost app → resolved bindings → `RemapConfig` |
| ActionsRingController | `UI/Ring/`: non-activating overlay panel |
| SmartActionRunner | `SmartActions/` |
| ScrollEngine | `Scrolling/`: wheel handling, smooth-scroll animator |
| PointerEngine | `Pointer/`: per-mouse tracking speed / acceleration via IOHIDServiceClient |
| DeviceManager | `Devices/`: IOHIDManager on its own thread, all mice + Logitech interfaces |
| HIDPPDriver | `Logitech/`: HID++ 2.0 messages, channel, device features, integration |
| SettingsStore | `Settings/`: Codable JSON in `~/Library/Application Support/MouseForge/settings.json` |
| UI | `UI/`: SwiftUI settings window, menu, onboarding, HUDs, test area |

Tests (`MouseForgeTests/`) cover:
- trigger timing, profile inheritance, gesture direction, ring slot selection, settings serialization;
- the scroll engine, Smart Actions, and presets;
- HID++ parsing and requests, against a simulated device.

## Private APIs and undocumented behavior

- **`CoreDockSendNotification`** (private, looked up at runtime): Mission
  Control, App Exposé, Show Desktop, Launchpad. Each has a public fallback.
- **Smart Zoom:** synthesizes a gesture event (type 29, subtype 22). Undocumented.
- **Do Not Disturb / Dictation:** post the key codes of the dedicated keys on
  recent Apple keyboards (178 / 176). Undocumented; may not work on every
  macOS version.
- **Notification Center:** presses the menu-bar clock through Accessibility.
- **Pointer:** `HIDMouseAcceleration` (tracking speed / acceleration) via
  the public `IOHIDServiceClient` API. Current macOS refuses
  `HIDPointerResolution`, so there's no separate speed multiplier.

## Known limitations

- Shortcut-based actions (Back, Spaces, screenshots, Spotlight, …) send
  macOS's *default* shortcuts. If you changed one in System Settings, record
  your shortcut with a "Keyboard Shortcut" action instead.
- Shortcuts macOS handles first (⌘Space, ⌘Tab, …) can't be *recorded*,
  although they can be sent.
- Brightness keys only affect displays that support them (usually built-in).
- Space switching needs Mission Control's "Move left/right a space"
  shortcuts enabled in System Settings.
- Smooth scrolling and modifier modes apply to notched wheels only.
  Trackpads and Magic Mouse are never changed.
- Logitech: HID++ 2.0 devices only (most mice from about 2014 on). HID++ 1.0
  Unifying-era devices show up as regular mice. Thumb-wheel step size and
  MX Master 4 haptic waveforms come from protocol documentation and may need
  tuning on real hardware.
- While the Settings window is in front, MouseForge itself is the frontmost
  app, so the All Applications profile is used. The Test Area can pretend
  any app profile is active.
