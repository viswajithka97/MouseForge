//
//  TriggerEditor.swift
//  MouseForge
//
//  Edits one trigger: shows what it does now (and whether that's inherited
//  or an override), any extra input the action needs, and the searchable,
//  categorized action library.
//

import SwiftUI

struct TriggerEditor: View {
    @ObservedObject var store: SettingsStore
    let trigger: TriggerKey
    let bundleID: String?

    private var current: (action: ActionConfig?, source: SettingsStore.BindingSource) {
        store.binding(for: trigger, in: bundleID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentCard
            if let action = current.action, let definition = ActionLibrary.action(action.actionID),
               definition.parameter != .none {
                ActionParameterEditor(definition: definition, config: action) { updated in
                    store.setBinding(updated, for: trigger, in: bundleID)
                }
            }
            actionList
        }
    }

    // MARK: - Current binding

    private var currentCard: some View {
        let (action, source) = current
        let isRemapped = action.map { !$0.isDefaultBehavior } ?? false

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: action.map(ActionLibrary.symbol(for:)) ?? "computermouse")
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(isRemapped ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trigger.kind.title + (trigger.modifiers.isEmpty ? "" : " with \(trigger.modifiers.symbols)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(action.map(ActionLibrary.displayName(for:)) ?? "Default Behavior")
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack {
                sourceBadge(source)
                Spacer()
                Button("Reset to Default") {
                    store.resetBinding(for: trigger, in: bundleID)
                }
                .disabled(!store.canReset(trigger, in: bundleID))
                .help(bundleID == nil
                      ? "Back to MouseForge's original setting"
                      : "Remove this override and use the All Applications setting")
            }

            Text(timingNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private func sourceBadge(_ source: SettingsStore.BindingSource) -> some View {
        switch source {
        case .appOverride:
            Badge(text: "Overrides All Applications", color: .orange)
        case .global where bundleID != nil:
            Badge(text: "Inherited from All Applications", color: .secondary)
        case .global, .unset:
            EmptyView()
        }
    }

    private var timingNote: String {
        let general = store.settings.general
        let interval = String(format: "%.2f s", general.doubleClickInterval)
        switch trigger.kind {
        case .hold:
            return String(format: "Fires after holding for %.2f s: that wait is how a hold is told apart from a click. For an instant action, use the Click tab. The delay can be changed in General ▸ Timing.", general.holdThreshold)
        case .gestureUp, .gestureDown, .gestureLeft, .gestureRight:
            return String(format: "Hold the button and move %@ at least %.0f points.",
                          trigger.kind.gestureDirection?.rawValue ?? "", general.gestureThreshold)
        case .doubleClick, .tripleClick:
            return "Clicks must be within \(interval) of each other."
        case .click:
            let app = store.settings.appProfile(for: bundleID)?.profile
            let resolved = Profile.resolved(global: store.settings.globalProfile, app: app)
            let waits = [TriggerKind.doubleClick, .tripleClick].contains { kind in
                let key = TriggerKey(button: trigger.button, kind: kind, modifiers: trigger.modifiers)
                return resolved[key].map { !$0.isDefaultBehavior } ?? false
            }
            if waits {
                return "Waits up to \(interval) after a click, because this button also has a Double or Triple Click action. Remove those to make it instant."
            }
            let hasHold = resolved[TriggerKey(button: trigger.button, kind: .hold, modifiers: trigger.modifiers)].map { !$0.isDefaultBehavior } ?? false
            let hasGesture = GestureDirection.allCases.contains { direction in
                resolved[TriggerKey(button: trigger.button, kind: direction.triggerKind, modifiers: trigger.modifiers)].map { !$0.isDefaultBehavior } ?? false
            }
            if hasHold || hasGesture || trigger.button == MouseButtons.middle {
                return "Fires as soon as you release the button (instantly, no delay)."
            }
            return "Fires the moment you press the button."
        }
    }

    // MARK: - Library

    private var actionList: some View {
        ActionLibraryList(currentID: current.action?.actionID) { action in
            select(action)
        }
    }

    private func select(_ action: any MouseAction) {
        guard current.action?.actionID != action.id || current.source != (bundleID == nil ? .global : .appOverride)
        else { return }
        // Keep any parameter already entered if it's the same action.
        var config = ActionConfig(action.id)
        if let existing = current.action, existing.actionID == action.id { config = existing }
        store.setBinding(config, for: trigger, in: bundleID)
    }
}

/// Searchable, categorized list of every library action.
struct ActionLibraryList: View {
    let currentID: ActionID?
    var exclude: Set<ActionID> = []
    /// Rows can be dragged (onto Actions Ring slots).
    var draggable = false
    let onSelect: (any MouseAction) -> Void

    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search actions", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))

            let groups = ActionLibrary.grouped(matching: search)
                .map { ($0.category, $0.actions.filter { !exclude.contains($0.id) }) }
                .filter { !$0.1.isEmpty }
            if groups.isEmpty {
                Text("No actions match “\(search)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.0) { category, actions in
                        Section(category.title) {
                            ForEach(actions, id: \.id) { action in
                                ActionRow(action: action, isCurrent: currentID == action.id) {
                                    onSelect(action)
                                }
                                .onDrag(if: draggable) { NSItemProvider(object: action.id.rawValue as NSString) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct ActionRow: View {
    let action: any MouseAction
    let isCurrent: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: action.symbol)
                    .frame(width: 22)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                Text(action.name)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// The extra input an action needs: a shortcut, some text, or a path.
struct ActionParameterEditor: View {
    let definition: any MouseAction
    let config: ActionConfig
    let update: (ActionConfig) -> Void

    private var text: Binding<String> {
        Binding(
            get: { config.text ?? "" },
            set: { newValue in
                var updated = config
                updated.text = newValue
                update(updated)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch definition.parameter {
            case .none:
                EmptyView()
            case .shortcut:
                Text("Shortcut").font(.caption).foregroundStyle(.secondary)
                ShortcutRecorder(combo: Binding(
                    get: { config.shortcut },
                    set: { newValue in
                        var updated = config
                        updated.shortcut = newValue
                        update(updated)
                    }
                ))
            case .text(let prompt, let multiline):
                Text(prompt).font(.caption).foregroundStyle(.secondary)
                if multiline {
                    TextEditor(text: text)
                        .font(.system(.body, design: definition.id == .typeText ? .default : .monospaced))
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                } else {
                    TextField(prompt, text: text)
                        .textFieldStyle(.roundedBorder)
                }
            case .url:
                Text("Web address").font(.caption).foregroundStyle(.secondary)
                TextField("https://example.com", text: text)
                    .textFieldStyle(.roundedBorder)
            case .smartAction:
                SmartActionParameterPicker(config: config, update: update)
            case .application, .file, .folder:
                HStack {
                    if let path = config.text, !path.isEmpty {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(FileManager.default.displayName(atPath: path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                    } else {
                        Text("Nothing chosen").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose…") {
                        if let path = AppPicker.choosePath(for: definition.parameter) { text.wrappedValue = path }
                    }
                }
            }
        }
    }
}

extension View {
    @ViewBuilder
    func onDrag(if enabled: Bool, _ data: @escaping () -> NSItemProvider) -> some View {
        if enabled { onDrag(data) } else { self }
    }
}

/// Picks which of the user's Smart Actions an action runs.
private struct SmartActionParameterPicker: View {
    let config: ActionConfig
    let update: (ActionConfig) -> Void
    @ObservedObject private var store = AppState.shared.store

    var body: some View {
        Text("Smart Action").font(.caption).foregroundStyle(.secondary)
        if store.settings.smartActions.isEmpty {
            HStack {
                Text("You haven't made any Smart Actions yet.").foregroundStyle(.secondary)
                Spacer()
                Button("Create…") { WindowManager.shared.showSettings(section: .smartActions) }
            }
        } else {
            HStack {
                Picker("Smart Action", selection: Binding(
                    get: { config.text ?? "" },
                    set: { newValue in
                        var updated = config
                        updated.text = newValue
                        update(updated)
                    }
                )) {
                    Text("Choose…").tag("")
                    ForEach(store.settings.smartActions) { smartAction in
                        Label(smartAction.name, systemImage: smartAction.symbol).tag(smartAction.id.uuidString)
                    }
                }
                .labelsHidden()
                Button("Edit…") { WindowManager.shared.showSettings(section: .smartActions) }
            }
        }
    }
}
