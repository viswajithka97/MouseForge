//
//  GestureEditor.swift
//  MouseForge
//
//  Four directions around the button, each with its own action, plus
//  one-click presets. Used in the side panel's Gesture tab and on the
//  Gestures screen.
//

import SwiftUI

struct GestureEditor: View {
    @ObservedObject var store: SettingsStore
    let button: MouseButtonNumber
    let bundleID: String?

    private func trigger(_ direction: GestureDirection) -> TriggerKey {
        TriggerKey(button: button, kind: direction.triggerKind)
    }

    private var current: [GestureDirection: ActionConfig] {
        var result: [GestureDirection: ActionConfig] = [:]
        for direction in GestureDirection.allCases {
            if let action = store.binding(for: trigger(direction), in: bundleID).action, !action.isDefaultBehavior {
                result[direction] = action
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Menu {
                    ForEach(GesturePreset.allCases) { preset in
                        Button {
                            apply(preset.actions)
                        } label: {
                            Label(preset.title, systemImage: preset.symbol)
                        }
                    }
                    Divider()
                    Button("Clear All Directions") { apply([:]) }
                } label: {
                    Text(GesturePreset.matching(current)?.title ?? (current.isEmpty ? "No gestures" : "Custom"))
                }
                .fixedSize()
                Spacer()
                Button("Reset to Default") {
                    for direction in GestureDirection.allCases {
                        store.resetBinding(for: trigger(direction), in: bundleID)
                    }
                }
                .disabled(!GestureDirection.allCases.contains { store.canReset(trigger($0), in: bundleID) })
            }

            VStack(spacing: 8) {
                directionCell(.up)
                HStack(spacing: 8) {
                    directionCell(.left)
                    Image(systemName: "computermouse.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                        .frame(width: 34)
                        .accessibilityHidden(true)
                    directionCell(.right)
                }
                directionCell(.down)
            }
            .frame(maxWidth: .infinity)

            if bundleID != nil, GestureDirection.allCases.contains(where: { store.binding(for: trigger($0), in: bundleID).source == .appOverride }) {
                Badge(text: "Overrides All Applications", color: .orange)
            }

            Text(String(format: "Hold %@ and move the mouse at least %.0f points. A click without moving still does the Click action. Threshold, hints, and pointer freezing are on the Gestures screen.",
                        MouseButtons.name(button), store.settings.general.gestureThreshold))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func directionCell(_ direction: GestureDirection) -> some View {
        VStack(spacing: 4) {
            Label(direction.title, systemImage: direction.arrowSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            ActionChooser(
                action: Binding(
                    get: { store.binding(for: trigger(direction), in: bundleID).action },
                    set: { newValue in
                        if let newValue {
                            store.setBinding(newValue, for: trigger(direction), in: bundleID)
                        } else {
                            store.resetBinding(for: trigger(direction), in: bundleID)
                        }
                    }
                ),
                placeholder: "None",
                exclude: [.defaultBehavior]
            )
            .frame(width: 150)
        }
    }

    private func apply(_ actions: [GestureDirection: ActionConfig]) {
        for direction in GestureDirection.allCases {
            if let action = actions[direction] {
                store.setBinding(action, for: trigger(direction), in: bundleID)
            } else if bundleID != nil {
                // Explicitly empty in this app even if All Applications has one.
                store.setBinding(ActionConfig(.doNothing), for: trigger(direction), in: bundleID)
            } else {
                store.resetBinding(for: trigger(direction), in: bundleID)
            }
        }
    }
}
