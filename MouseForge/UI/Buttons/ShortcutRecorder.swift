//
//  ShortcutRecorder.swift
//  MouseForge
//
//  Click, then press a key combination to record it. Esc cancels,
//  Delete clears.
//
//  Limitation: shortcuts macOS itself handles first (⌘Space, ⌘Tab, …)
//  never reach the app, so they can't be recorded here.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 140)
                    .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
            }
            .help(isRecording ? "Press a key combination. Esc cancels, Delete clears." : "Click to record a shortcut")

            if combo != nil && !isRecording {
                Button("Clear") { combo = nil }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return "Type shortcut…" }
        return combo?.displayString ?? "Record Shortcut"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        // A local monitor sees key presses in our own windows before menus
        // and text fields do, so ⌘W etc. are recorded instead of acted on.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = ModifierSet(event.modifierFlags)
            switch Int(event.keyCode) {
            case kVK_Escape where modifiers.isEmpty:
                break
            case kVK_Delete where modifiers.isEmpty, kVK_ForwardDelete where modifiers.isEmpty:
                combo = nil
            default:
                combo = KeyCombo(Int(event.keyCode), modifiers)
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
