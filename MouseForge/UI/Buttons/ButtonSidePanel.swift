//
//  ButtonSidePanel.swift
//  MouseForge
//
//  Configures one button: a tab per trigger (Click, Double, Triple, Hold,
//  Gesture, Modifier), each showing the current action and the library.
//

import SwiftUI

struct ButtonSidePanel: View {
    @ObservedObject var store: SettingsStore
    let button: MouseButtonNumber
    let bundleID: String?
    let close: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case click, double, triple, hold, gesture, modifier

        var id: String { rawValue }

        var title: String {
            switch self {
            case .click: return "Click"
            case .double: return "Double"
            case .triple: return "Triple"
            case .hold: return "Hold"
            case .gesture: return "Gesture"
            case .modifier: return "Modifier"
            }
        }

        var kind: TriggerKind? {
            switch self {
            case .click: return .click
            case .double: return .doubleClick
            case .triple: return .tripleClick
            case .hold: return .hold
            case .gesture, .modifier: return nil
            }
        }
    }

    @State private var tab: Tab = .click
    @State private var modifiers: ModifierSet = [.shift]
    @State private var modifierKind: TriggerKind = .click
    @State private var confirmUnlock = false

    private var isLocked: Bool {
        MouseButtons.isPrimary(button) && !store.settings.general.allowPrimaryButtonRemap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLocked {
                lockedView
            } else {
                Picker("Trigger", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                switch tab {
                case .gesture:
                    ScrollView {
                        GestureEditor(store: store, button: button, bundleID: bundleID)
                    }
                case .modifier:
                    modifierControls
                    if modifiers.isEmpty {
                        Text("Choose at least one modifier key.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        TriggerEditor(
                            store: store,
                            trigger: TriggerKey(button: button, kind: modifierKind, modifiers: modifiers),
                            bundleID: bundleID
                        )
                    }
                default:
                    TriggerEditor(
                        store: store,
                        trigger: TriggerKey(button: button, kind: tab.kind ?? .click),
                        bundleID: bundleID
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .unlockPrimaryButtonsAlert(isPresented: $confirmUnlock, store: store)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MouseButtons.name(button)).font(.title3.weight(.semibold))
                Text(store.settings.appProfile(for: bundleID)?.name ?? "All Applications")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
    }

    private var lockedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Left and right click are locked", systemImage: "lock.fill")
                .font(.headline)
            Text("So you can't accidentally lose the ability to click, MouseForge leaves your main buttons alone unless you unlock them.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Unlock…") { confirmUnlock = true }
            Spacer()
        }
    }

    private var modifierControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("While holding")
                ModifierToggles(modifiers: $modifiers)
            }
            Picker("Trigger", selection: $modifierKind) {
                ForEach(TriggerKind.pressKinds, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let combos = configuredModifierCombos
            if !combos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Set:").font(.caption).foregroundStyle(.secondary)
                        ForEach(combos, id: \.self) { trigger in
                            Button("\(trigger.modifiers.symbols) \(trigger.kind.title)") {
                                modifiers = trigger.modifiers
                                modifierKind = trigger.kind
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    /// Modifier bindings that exist for this button (own or inherited).
    private var configuredModifierCombos: [TriggerKey] {
        let app = store.settings.appProfile(for: bundleID)?.profile
        return Profile.resolved(global: store.settings.globalProfile, app: app).keys
            .filter { $0.button == button && !$0.modifiers.isEmpty }
            .sorted { ($0.modifiers.rawValue, $0.kind.rawValue) < ($1.modifiers.rawValue, $1.kind.rawValue) }
    }
}
