//
//  ScrollingScreen.swift
//  MouseForge
//
//  Wheel and thumb-wheel settings, per app. An app either uses the All
//  Applications settings or its own full copy.
//

import SwiftUI

struct ScrollingScreen: View {
    @ObservedObject var store: SettingsStore
    let bundleID: String?
    @StateObject private var conflicts = ScrollConflicts()

    private var appName: String? { store.settings.appProfile(for: bundleID)?.name }
    private var appIndex: Int? { bundleID.flatMap { store.settings.appProfileIndex(for: $0) } }

    private var hasOwnScroll: Bool { appIndex.map { store.settings.appProfiles[$0].profile.scroll != nil } ?? true }
    private var hasOwnThumb: Bool { appIndex.map { store.settings.appProfiles[$0].profile.thumbWheel != nil } ?? true }

    private var scroll: Binding<ScrollSettings> {
        Binding(
            get: { store.settings.scroll(for: bundleID) },
            set: { newValue in
                if let index = appIndex {
                    store.settings.appProfiles[index].profile.scroll = newValue
                } else {
                    store.settings.globalProfile.scroll = newValue
                }
            }
        )
    }

    private var thumb: Binding<ThumbWheelSettings> {
        Binding(
            get: { store.settings.thumbWheel(for: bundleID) },
            set: { newValue in
                if let index = appIndex {
                    store.settings.appProfiles[index].profile.thumbWheel = newValue
                } else {
                    store.settings.globalProfile.thumbWheel = newValue
                }
            }
        )
    }

    var body: some View {
        Form {
            if !conflicts.running.isEmpty {
                Section {
                    let names = conflicts.running.map(ScrollConflicts.displayName).joined(separator: ", ")
                    Label("\(names) is also changing your scrolling. Two scroll apps at once make scrolling jumpy or stop it working. Turn off its scrolling features, or quit it.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if let appName, let index = appIndex {
                Section {
                    Toggle("Use custom scrolling in \(appName)", isOn: Binding(
                        get: { hasOwnScroll },
                        set: { store.settings.appProfiles[index].profile.scroll = $0 ? store.settings.scroll(for: nil) : nil }
                    ))
                    if hasOwnScroll {
                        Badge(text: "Overrides All Applications", color: .orange)
                    }
                }
            }

            Section {
                Toggle("Smooth scrolling", isOn: scroll.smooth)
                if scroll.wrappedValue.smooth {
                    slider("Glide", value: scroll.inertia, in: 0...1, left: "Short", right: "Long")
                }
                slider("Speed", value: scroll.speed, in: ScrollSettings.speedRange, left: "Slow", right: "Fast", format: "%.2f×")
                slider("Acceleration", value: scroll.acceleration, in: ScrollSettings.accelerationRange, left: "None", right: "Strong", format: "%.1f")
                Toggle("Reverse scroll direction for mice", isOn: scroll.reverseMouse)
            } header: {
                Text("Mouse Wheel")
            } footer: {
                Text("Only notched mouse wheels are changed. Trackpads and Magic Mouse keep macOS's own scrolling.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!hasOwnScroll)

            Section {
                modifierRow("Precise (slow)", scroll.preciseModifiers)
                modifierRow("Quick (fast)", scroll.quickModifiers)
                modifierRow("Horizontal", scroll.horizontalModifiers)
                modifierRow("Zoom", scroll.zoomModifiers)
            } header: {
                Text("While Holding")
            } footer: {
                Text("Hold exactly these keys while scrolling. Turn all keys off to disable a mode.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!hasOwnScroll)

            if let appName, let index = appIndex {
                Section {
                    Toggle("Use a custom thumb wheel in \(appName)", isOn: Binding(
                        get: { hasOwnThumb },
                        set: { store.settings.appProfiles[index].profile.thumbWheel = $0 ? store.settings.thumbWheel(for: nil) : nil }
                    ))
                }
            }

            Section {
                Picker("Thumb wheel does", selection: thumb.mode) {
                    ForEach(ThumbWheelMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Reverse direction", isOn: thumb.invert)
                slider(thumb.wrappedValue.mode == .horizontalScroll ? "Speed" : "Sensitivity",
                       value: thumb.speed, in: 0.25...4, left: "Low", right: "High", format: "%.2f×")
                if thumb.wrappedValue.mode == .custom {
                    LabeledContent("Turn left") {
                        ActionChooser(action: thumb.customLeft, placeholder: "None", exclude: [.defaultBehavior])
                    }
                    LabeledContent("Turn right") {
                        ActionChooser(action: thumb.customRight, placeholder: "None", exclude: [.defaultBehavior])
                    }
                }
            } header: {
                Text("Thumb Wheel / Horizontal Wheel")
            } footer: {
                Text("Works with any horizontal or tilt wheel. Logitech thumb wheels get finer control on the Device screen.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!hasOwnThumb)
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        left: String, right: String, format: String? = nil) -> some View {
        LabeledContent(title) {
            HStack {
                Text(left).font(.caption).foregroundStyle(.secondary)
                Slider(value: value, in: range)
                Text(right).font(.caption).foregroundStyle(.secondary)
                if let format {
                    Text(String(format: format, value.wrappedValue))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private func modifierRow(_ title: String, _ modifiers: Binding<ModifierSet>) -> some View {
        LabeledContent(title) {
            ModifierToggles(modifiers: modifiers)
        }
    }
}
