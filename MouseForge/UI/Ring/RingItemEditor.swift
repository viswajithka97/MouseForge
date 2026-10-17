//
//  RingItemEditor.swift
//  MouseForge
//
//  Makes or edits a user's own Actions Ring item: a name, an icon, and
//  what it does (a shortcut, a Terminal command, a script, a link, …).
//

import SwiftUI

struct RingItemEditor: View {
    let title: String
    let onSave: (ActionConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var item: ActionConfig

    /// The kinds of things a custom item can do.
    static let kinds: [ActionID] = [
        .keyboardShortcut, .runInTerminal, .shellScript, .appleScript, .openURL,
        .openApp, .openFile, .openFolder, .typeText, .runShortcut, .smartAction,
    ]

    /// Icons to choose from.
    static let symbols: [String] = [
        "star", "bolt", "play.fill", "ladybug", "hammer", "apple.terminal",
        "chevron.left.forwardslash.chevron.right", "curlybraces", "ant", "testtube.2", "cpu", "server.rack",
        "iphone", "desktopcomputer", "globe", "link", "doc", "folder",
        "shippingbox", "cube", "arrow.clockwise", "arrow.up.circle", "tray.and.arrow.down", "paperplane",
        "envelope", "bubble.left", "bookmark", "flag", "tag", "pin",
        "heart", "flame", "leaf", "sparkles", "wand.and.stars", "gearshape",
        "paintbrush", "camera", "music.note", "cloud", "keyboard", "text.cursor",
        "magnifyingglass", "house", "person", "lock", "checkmark.circle", "xmark.circle",
        "list.bullet", "square.and.pencil", "doc.on.doc", "scissors", "trash", "number",
    ]

    init(title: String, item: ActionConfig?, onSave: @escaping (ActionConfig) -> Void) {
        self.title = title
        self.onSave = onSave
        _item = State(initialValue: item ?? ActionConfig(.keyboardShortcut, symbol: "star"))
    }

    private var definition: (any MouseAction)? { ActionLibrary.action(item.actionID) }

    private var kinds: [ActionID] {
        Self.kinds.contains(item.actionID) ? Self.kinds : [item.actionID] + Self.kinds
    }

    private var name: Binding<String> {
        Binding(get: { item.label ?? "" }, set: { item.label = $0.isEmpty ? nil : $0 })
    }

    private var isComplete: Bool {
        guard !(item.label ?? "").trimmingCharacters(in: .whitespaces).isEmpty, let definition else { return false }
        switch definition.parameter {
        case .none: return true
        case .shortcut: return item.shortcut != nil
        default: return !(item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                Image(systemName: ActionLibrary.symbol(for: item))
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.accentColor.opacity(0.14)))
                TextField("Name shown on the ring, e.g. Flutter Run", text: name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 12), spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button { item.symbol = symbol } label: {
                            Image(systemName: symbol)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6).fill(
                                    item.symbol == symbol ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.05)
                                ))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
            }

            Picker("What it does", selection: Binding(
                get: { item.actionID },
                set: { newKind in
                    guard newKind != item.actionID else { return }
                    item = ActionConfig(newKind, label: item.label, symbol: item.symbol)
                }
            )) {
                ForEach(kinds, id: \.self) { kind in
                    if let action = ActionLibrary.action(kind) {
                        Label(action.name, systemImage: action.symbol).tag(kind)
                    }
                }
            }

            if let definition, definition.parameter != .none {
                ActionParameterEditor(definition: definition, config: item) { item = $0 }
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = item
                    saved.label = saved.label?.trimmingCharacters(in: .whitespaces)
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isComplete)
            }
        }
        .padding(20)
        .frame(width: 480, height: 560)
    }

    private var hint: String? {
        switch item.actionID {
        case .keyboardShortcut:
            return "Presses the shortcut in the app you're using. Any menu command with a shortcut works; you can also add your own in the app's keyboard settings."
        case .runInTerminal:
            return "Opens a new Terminal window and runs the command there, so you see its output. macOS asks once to let MouseForge control Terminal."
        case .shellScript:
            return "Runs silently in the background with zsh. Use Run in Terminal for commands you want to watch or that keep running."
        default:
            return nil
        }
    }
}
