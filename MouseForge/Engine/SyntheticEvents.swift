//
//  SyntheticEvents.swift
//  MouseForge
//
//  Creates and posts fake keyboard, mouse, and media-key events. Every
//  event we post is tagged with a marker value so our own event tap
//  recognises it and lets it through instead of remapping it again.
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum SyntheticEvents {
    /// Stored in the `eventSourceUserData` field of everything we post
    /// ("MFSE" in ASCII).
    static let marker: Int64 = 0x4D46_5345

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    private static func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    private static var source: CGEventSource? { CGEventSource(stateID: .hidSystemState) }

    static var cursorLocation: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    // MARK: - Mouse

    private static func mouseTypes(for button: MouseButtonNumber) -> (down: CGEventType, up: CGEventType) {
        switch button {
        case MouseButtons.left: return (.leftMouseDown, .leftMouseUp)
        case MouseButtons.right: return (.rightMouseDown, .rightMouseUp)
        default: return (.otherMouseDown, .otherMouseUp)
        }
    }

    private static func mouseEvent(_ type: CGEventType, button: MouseButtonNumber, clickState: Int) -> CGEvent? {
        let event = CGEvent(
            mouseEventSource: source, mouseType: type, mouseCursorPosition: cursorLocation,
            mouseButton: CGMouseButton(rawValue: UInt32(button - 1)) ?? .center
        )
        event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        return event
    }

    /// Posts `count` down/up pairs, numbered as a real double/triple click.
    static func click(button: MouseButtonNumber, count: Int = 1) {
        let types = mouseTypes(for: button)
        for n in 1...max(count, 1) {
            post(mouseEvent(types.down, button: button, clickState: n))
            post(mouseEvent(types.up, button: button, clickState: n))
        }
    }

    static func buttonDown(_ button: MouseButtonNumber) {
        post(mouseEvent(mouseTypes(for: button).down, button: button, clickState: 1))
    }

    // MARK: - Keyboard

    /// Keys that macOS reports with the fn (and, for arrows, keypad) flag.
    /// System shortcuts such as ⌃→ (next Space) only match with them set.
    private static func extraFlags(for keyCode: CGKeyCode) -> CGEventFlags {
        switch Int(keyCode) {
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            return [.maskSecondaryFn, .maskNumericPad]
        case kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Help,
             kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9,
             kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16:
            return .maskSecondaryFn
        default:
            return []
        }
    }

    /// Presses and releases a shortcut, including the modifier keys
    /// themselves (some system features, like the ⌘-Tab switcher, need to
    /// see the modifier go down and up).
    static func press(_ combo: KeyCombo) {
        let keyCode = CGKeyCode(combo.keyCode)
        let modifierKeys = ModifierSet.ordered.filter { combo.modifiers.contains($0) }

        var flags: CGEventFlags = []
        for modifier in modifierKeys {
            flags.insert(modifier.cgFlags)
            postKey(modifier.leftKeyCode!, down: true, flags: flags)
        }
        let keyFlags = flags.union(extraFlags(for: keyCode))
        postKey(keyCode, down: true, flags: keyFlags)
        postKey(keyCode, down: false, flags: keyFlags)
        for modifier in modifierKeys.reversed() {
            flags.remove(modifier.cgFlags)
            postKey(modifier.leftKeyCode!, down: false, flags: flags)
        }
    }

    static func postKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
        event?.flags = flags
        post(event)
    }

    /// Types arbitrary text (any language, emoji) by attaching the
    /// characters to key events directly, independent of keyboard layout.
    /// Call off the event-tap thread: it pauses briefly between chunks.
    static func type(_ text: String) {
        let units = Array(text.utf16)
        let chunkSize = 16 // Some apps drop longer strings per event.
        var start = 0
        while start < units.count {
            let end = min(start + chunkSize, units.count)
            var chunk = Array(units[start..<end])
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.flags = []
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                post(event)
            }
            start = end
            usleep(4_000)
        }
    }

    // MARK: - Scrolling

    /// A smooth (pixel, trackpad-style) scroll event with a gesture phase
    /// (1 began, 2 changed, 4 ended).
    static func postPixelScroll(dx: Int, dy: Int, phase: Int64, flags: CGEventFlags) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.flags = flags
        post(event)
    }

    // MARK: - Media & special keys

    /// Codes from IOKit's ev_keymap.h (NX_KEYTYPE_*), the "aux control"
    /// keys on Apple keyboards.
    enum MediaKey: Int32 {
        case volumeUp = 0
        case volumeDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case play = 16
        case next = 19 // NX_KEYTYPE_FAST, what the ⏭ key sends
        case previous = 20 // NX_KEYTYPE_REWIND, what the ⏮ key sends
    }

    static func press(_ key: MediaKey) {
        for down in [true, false] {
            let state: Int = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: (Int(key.rawValue) << 16) | (state << 8),
                data2: -1
            )
            post(event?.cgEvent)
        }
    }

    // MARK: - Gestures (undocumented)

    /// Simulates a two-finger double tap ("Smart Zoom"). Uses undocumented
    /// event values: type 29 is the gesture event type and field 110 holds
    /// the HID gesture subtype, where 22 means "zoom toggle".
    static func smartZoom() {
        guard
            let event = CGEvent(source: nil),
            let gestureType = CGEventType(rawValue: 29),
            let subtypeField = CGEventField(rawValue: 110)
        else { return }
        event.type = gestureType
        event.location = cursorLocation
        event.setIntegerValueField(subtypeField, value: 22)
        post(event)
    }
}
