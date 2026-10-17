//
//  ActionChooser.swift
//  MouseForge
//
//  A compact way to pick an action anywhere in the UI: a button showing
//  the current action that opens a popover with the parameter editor, an
//  optional custom name, and the searchable library.
//

import SwiftUI

struct ActionChooser: View {
    @Binding var action: ActionConfig?
    /// Text for the "nothing chosen" state.
    var placeholder = "Choose Action…"
    /// Actions that make no sense in this context (e.g. a Smart Action
    /// step can't open the Actions Ring).
    var exclude: Set<ActionID> = []
    var allowsClear = true

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                if let action {
                    Image(systemName: ActionLibrary.symbol(for: action)).frame(width: 18)
                    Text(ActionLibrary.displayName(for: action)).lineLimit(1)
                } else {
                    Text(placeholder).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 150)
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            ActionChooserPanel(action: $action, exclude: exclude, allowsClear: allowsClear)
                .frame(width: 360, height: 480)
                .padding(12)
        }
    }
}

struct ActionChooserPanel: View {
    @Binding var action: ActionConfig?
    var exclude: Set<ActionID> = []
    var allowsClear = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let current = action, let definition = ActionLibrary.action(current.actionID) {
                HStack {
                    Image(systemName: definition.symbol).foregroundStyle(Color.accentColor)
                    Text(ActionLibrary.displayName(for: current)).font(.headline).lineLimit(1)
                    Spacer()
                    if allowsClear {
                        Button("Clear") { action = nil }
                    }
                }
                if definition.parameter != .none {
                    ActionParameterEditor(definition: definition, config: current) { action = $0 }
                }
                TextField("Custom name (optional)", text: Binding(
                    get: { current.label ?? "" },
                    set: { newValue in
                        var updated = current
                        updated.label = newValue.isEmpty ? nil : newValue
                        action = updated
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            ActionLibraryList(currentID: action?.actionID, exclude: exclude) { picked in
                if action?.actionID != picked.id { action = ActionConfig(picked.id) }
            }
        }
    }
}
