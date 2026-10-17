//
//  GesturesScreen.swift
//  MouseForge
//
//  Pick a gesture button and its four directions (per app), and set how
//  gestures feel: movement threshold, on-screen hint, repeat, pointer
//  freezing.
//

import SwiftUI

struct GesturesScreen: View {
    @ObservedObject var store: SettingsStore
    let bundleID: String?
    /// Every configurable button, Logitech controls included.
    let buttons: [MouseButtonNumber]

    @State private var selectedButton: MouseButtonNumber?

    private var button: MouseButtonNumber {
        selectedButton
            ?? store.gestureButtons(in: bundleID).first
            ?? buttons.first { $0 == LogitechButtons.buttonNumber(for: LogitechButtons.gestureButtonCID) }
            ?? MouseButtons.middle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(store.settings.appProfile(for: bundleID)?.name ?? "All Applications")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Picker("Gesture button", selection: Binding(get: { button }, set: { selectedButton = $0 })) {
                        ForEach(buttons, id: \.self) { b in
                            Text(MouseButtons.name(b) + (store.gestureButtons(in: bundleID).contains(b) ? "  •" : "")).tag(b)
                        }
                    }
                    .frame(maxWidth: 280)
                }

                GestureEditor(store: store, button: button, bundleID: bundleID)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))

                let configured = store.gestureButtons(in: bundleID)
                if !configured.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Buttons with gestures").font(.headline)
                        ForEach(configured, id: \.self) { b in
                            Button {
                                selectedButton = b
                            } label: {
                                HStack {
                                    Text(MouseButtons.name(b)).frame(width: 140, alignment: .leading)
                                    ForEach(GestureDirection.allCases, id: \.self) { direction in
                                        Label(summary(b, direction), systemImage: direction.arrowSymbol)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .font(.callout)
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity)

            Divider()

            Form {
                Section("How gestures feel (all apps)") {
                    LabeledContent("Movement threshold") {
                        HStack {
                            Slider(value: $store.settings.general.gestureThreshold, in: GeneralSettings.gestureThresholdRange, step: 5)
                            Text(String(format: "%.0f pt", store.settings.general.gestureThreshold))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Toggle("Show a hint when a gesture fires", isOn: $store.settings.general.gestureHints)
                    Toggle("Keep the pointer still while gesturing", isOn: $store.settings.general.gestureFreezesPointer)
                    Toggle("Repeat while moving", isOn: $store.settings.general.gestureRepeats)
                }
                Section {
                    Text("Repeat fires the action again every time you move another threshold's distance, e.g. several Space switches or volume steps in one hold.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)
        }
    }

    private func summary(_ button: MouseButtonNumber, _ direction: GestureDirection) -> String {
        let action = store.binding(for: TriggerKey(button: button, kind: direction.triggerKind), in: bundleID).action
        guard let action, !action.isDefaultBehavior, action.actionID != .doNothing else { return "–" }
        return ActionLibrary.displayName(for: action)
    }
}
