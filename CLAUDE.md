## Progress (resume here)
Signing: Automatic, team P7RH8T36YW (Personal Team), bundle id com.mouse.forge.MouseForge. Build: `xcodebuild -project MouseForge.xcodeproj -scheme MouseForge -allowProvisioningUpdates build`; tests: same with `test`.
- [x] Phase 1: menu-bar app, permissions onboarding, event tap logging
- [x] Phase 2: remapping engine, Buttons UI, per-app profiles, JSON persistence, live test area, permission/signing fixes
- [x] Phase 3: Actions Ring (overlay, hold/click modes, per-app + built-in rings, drag-and-drop editor)
- [x] Phase 4: Gestures (4 directions, presets, hint, freeze, repeat) + one-click suggested presets for popular apps
- [x] Phase 5: Smart Actions (editor, runner, nesting, templates, assignable everywhere)
- [x] Phase 6: Scrolling (smooth/inertia, reverse, speed, accel, modifier modes, thumb wheel modes, per app) + pointer (speed, acceleration via IOHIDServiceClient)
- [x] Phase 7: Logitech basics (HID++ 2.0 channel + feature discovery, receivers + Bluetooth, name, battery + low-battery alerts, DPI + presets + Cycle DPI, SmartShift, hi-res wheel; menu shows device + battery)
- [x] Phase 8: Logitech advanced (extra buttons + gesture button diverted as virtual buttons only when bound, thumb wheel diversion when needed, Easy-Switch channel, MX Master 4 haptics + ring/gesture ticks, release on quit)
- [x] Phase 9: Polish (backup/restore/reset, launch at login, onboarding refresh, perf pass, app icon, docs/SIGNING.md + README)

You are an expert macOS developer specializing in Swift, SwiftUI, AppKit, Quartz Event Services, and IOKit HID. We are building "MouseForge", a native macOS menu-bar app that matches the features of Logitech Options+ (for the MX Master 4 and other mice) plus everything in Mac Mouse Fix. All code, UI design, icons, and mouse illustrations must be original. Do not copy code, images, or assets from Logitech or Mac Mouse Fix. Behavior may be inspired by them.

## Tech stack & constraints
- Swift 5.9+, SwiftUI for UI, AppKit where needed (NSPanel overlays, NSStatusItem, NSWorkspace)
- macOS 13+, Apple Silicon + Intel, App Sandbox disabled
- Menu-bar app (LSUIElement), launch at login via SMAppService
- CGEventTap (active) for intercepting/replacing mouse, scroll, and keyboard events
- IOKit HID (IOHIDManager) for device detection and raw HID / HID++ access
- Accessibility + Input Monitoring permissions with onboarding (already built in Phase 1)
- Settings as Codable JSON in Application Support, with backup/restore import/export
- Event tap callbacks must never block; heavy work goes off the tap thread
- Safety: left/right click are never remapped unless the user explicitly unlocks it; global kill switch shortcut (Ctrl+Option+Cmd+M) instantly disables all remapping

## 1. Button customization (any mouse)
- Detect all buttons dynamically (3, 4, 5, and beyond; Logitech extra buttons via HID++ later)
- Triggers per button: single click, double click, triple click, click-and-hold, click-and-drag (gesture), and modifier combos (e.g., Shift + Button 4)
- If a button has no double-click action, fire single click instantly (no delay)
- Configurable timing for double click and hold thresholds

## 2. Action library (searchable, categorized)
- Navigation: back, forward, middle click, switch tabs, close tab, reopen tab, scroll to top/bottom
- Window & desktop: Mission Control, App Exposé, Show Desktop, Launchpad, switch Space left/right, minimize, full screen, close window, switch app (Cmd+Tab), hide app
- Editing: copy, paste, cut, undo, redo, select all, find, save
- Media: play/pause, next/previous track, volume up/down/mute, brightness up/down
- System: screenshot (full/area/window), screen recording, lock screen, sleep display, Spotlight, Do Not Disturb, dictation, emoji picker, Look Up, Smart Zoom, Notification Center
- Launch: open app, file, folder, or URL
- Custom: recorded keyboard shortcut, type text snippet, AppleScript, shell script, Shortcuts.app shortcut
- Special: Actions Ring, Smart Action, DPI cycle (Logitech), Do nothing, Default behavior
- Each action has an SF Symbol icon and display name

## 3. App-specific customization (per-app profiles)
- "All Applications" global profile, plus per-app profiles added from installed apps (show app icons)
- Each app profile can override any button, trigger, gesture, scroll, thumb wheel, and Actions Ring setting; unset values inherit from global
- Detect frontmost app via NSWorkspace and switch profiles instantly
- Built-in suggested presets for popular apps (Safari, Chrome, Firefox, Finder, VS Code, Xcode, Photoshop, Figma, Final Cut Pro, Premiere, Zoom, Teams, Slack, Microsoft Office, Spotify) that the user can apply with one click
- Profile indicator in the menu bar menu

## 4. Actions Ring (radial overlay menu)
- Assign "Actions Ring" to any button (default: hold a side button or the MX Master 4 haptic/thumb button)
- While held, show a circular overlay centered at the cursor: a transparent non-activating NSPanel floating above all windows, working on all Spaces and over full-screen apps
- 8 customizable slots plus a center cancel zone; each slot shows an icon and label
- Select by moving toward a slot and releasing the button, or by clicking a slot; Esc or releasing in the center cancels
- Ring contents change per frontmost app (app-specific rings, falling back to the global ring)
- Default rings for popular apps (e.g., browser: new tab, close tab, reopen tab, bookmarks, history, downloads, private window, refresh)
- Smooth open/close and hover animations, light/dark mode, accessible sizing
- Ring editor in settings: drag actions into slots, per app
- Later phase: haptic tick on MX Master 4 when hovering a slot

## 5. Gestures
- Gesture button (or any button): hold + move up/down/left/right, each direction mapped to an action, per app
- Presets: Windows & Desktop navigation, Media control, Zoom, App navigation, Custom
- Configurable movement threshold; gesture overlay hint optional

## 6. Smart Actions (macros)
- Multi-step action sequences triggered by a button: e.g., open app, wait 1s, type text, press shortcut, open URL
- Step types: any library action, delay, type text, open app/URL/file
- Optional template library of example Smart Actions
- Smart Actions are assignable to buttons, gestures, and Actions Ring slots

## 7. Scrolling & thumb wheel
- Smooth scrolling with configurable inertia (Mac Mouse Fix style), on/off per app
- Reverse direction for the mouse independently of the trackpad
- Scroll speed and acceleration curve
- Precise scroll, quick scroll, horizontal scroll, and zoom while holding configurable modifiers
- Thumb wheel (Logitech): horizontal scroll, zoom, tab switching, volume, brightness, timeline scrubbing, custom, per app, with direction and speed settings

## 8. Pointer
- Pointer speed and custom acceleration curve, option to disable acceleration
- DPI presets and DPI cycle button (Logitech)

## 9. Logitech features (HID++ 2.0, Bluetooth + Logi Bolt)
Original HID++ implementation (Solaar/libratbag only for protocol understanding):
- Device discovery, model name, feature enumeration, connection type
- Battery level and low-battery notifications
- DPI read/write
- SmartShift: ratchet/free-spin mode and sensitivity threshold
- Hi-res wheel toggle
- Divert extra buttons and the gesture button via REPROG_CONTROLS_V4
- Thumb wheel diversion
- Easy-Switch: show which channel the mouse is on
- MX Master 4 haptic feedback: discover the feature if possible; on/off and intensity; haptic ticks for Actions Ring and gestures; fail gracefully
- Hide any unsupported feature in the UI instead of showing errors

## 10. UI design
- Settings window with sidebar: Devices, Buttons, Actions Ring, Gestures, Smart Actions, Scrolling, Pointer, Device (Logitech), App Profiles, General
- Top app-selector bar: "All Applications" plus app icons for each app profile, with a "+" to add an app; the whole screen reflects the selected app
- Buttons screen: original, clean mouse illustration (generic mouse + MX Master-style shape drawn in SwiftUI/vector) with clickable hotspots on each button; hovering highlights the button; clicking opens a side panel
- Side panel: trigger tabs (Click / Double Click / Hold / Gesture / Modifier), searchable categorized action list with icons, shortcut recorder, "Reset to default", and a badge showing when a setting overrides the global profile
- Live test area for scroll, gestures, and clicks
- Menu-bar menu: enable/disable, current device and battery, active profile, open settings, quit
- Native macOS look, light/dark mode, smooth animations, keyboard accessible

## Architecture
- Modules: EventTapEngine, TriggerDetector, ActionLibrary, ActionExecutor, ProfileManager, AppWatcher, ActionsRingController, GestureRecognizer, SmartActionRunner, ScrollEngine, PointerEngine, DeviceManager, HIDPPDriver, SettingsStore, UI
- Protocol-based actions and triggers so new ones are easy to add
- Thread-safe; dedicated high-priority event thread
- Unit tests for trigger timing, profile inheritance, gesture direction detection, Actions Ring slot selection, and settings serialization

## Phases (stop after each for me to test)
1. DONE: menu-bar app, permissions onboarding, event tap logging
2. Remapping engine + Buttons UI: active event tap, kill switch, TriggerDetector (click/double/hold/modifiers), full ActionLibrary + ActionExecutor, Buttons screen with mouse illustration, hotspots, side panel, shortcut recorder, per-app profiles with app-selector bar and inheritance, JSON persistence
3. Actions Ring: overlay, selection logic, per-app rings, ring editor, default rings for popular apps
4. Gestures + app presets: GestureRecognizer, gesture presets, suggested presets for popular apps
5. Smart Actions: macro editor and runner, templates
6. Scrolling + pointer: smooth scroll engine, all scroll modifiers, pointer acceleration
7. Logitech basics: HID++ discovery, battery, DPI, SmartShift, hi-res wheel
8. Logitech advanced: button/gesture button/thumb wheel diversion, Easy-Switch status, haptics
9. Polish: backup/restore, launch at login, onboarding refresh, performance pass, signing and notarization guide

For each phase: explain the approach, list files created/changed, write complete code, and explain how to build and test. Call out private APIs, required permissions, and known limitations.
