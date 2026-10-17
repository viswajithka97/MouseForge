//
//  ActionsRingScreen.swift
//  MouseForge
//
//  Ring editor: drag actions from the library onto slots (or slot onto
//  slot to swap), click a slot to fine-tune it, per app.
//

import SwiftUI
import UniformTypeIdentifiers

struct ActionsRingScreen: View {
    @ObservedObject var store: SettingsStore
    /// nil = All Applications.
    let bundleID: String?

    @State private var editingSlot: Int?
    @State private var dropTarget: Int?
    @State private var tab: LibraryTab = .myItems
    @State private var itemEditor: ItemEditorTarget?

    private enum LibraryTab: Hashable { case myItems, suggested, all }

    /// What the item editor sheet is editing.
    private enum ItemEditorTarget: Identifiable {
        case new
        case myItem(Int)
        case slot(Int)

        var id: String {
            switch self {
            case .new: return "new"
            case .myItem(let index): return "item\(index)"
            case .slot(let index): return "slot\(index)"
            }
        }
    }

    /// Commands suggested for the selected app, if MouseForge knows it.
    private var preset: AppPreset? {
        bundleID.flatMap(AppPresetCatalog.preset(for:))
    }

    private var resolved: (ring: RingConfig, source: RingSource) {
        store.settings.ring(for: bundleID)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                triggerInfo
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Drag an action onto a slot, drag one slot onto another to swap them, or click a slot to choose its action. Right-click a slot to rename it, change its icon, or save it to My Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(minWidth: 440, maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("Actions", selection: $tab) {
                    Text("My Items").tag(LibraryTab.myItems)
                    if let preset { Text(preset.name).tag(LibraryTab.suggested) }
                    Text("All Actions").tag(LibraryTab.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .myItems:
                    myItems
                case .suggested where preset != nil:
                    SuggestedActionsList(actions: preset?.suggestions ?? []) { place($0) }
                    Text("\(preset?.name ?? "")'s own keyboard shortcuts. Click one to put it in the selected or first empty slot, or drag it onto a slot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    ActionLibraryList(currentID: nil, exclude: [.actionsRing, .defaultBehavior], draggable: true) { action in
                        place(ActionConfig(action.id))
                    }
                    Text("Click an action to put it in the selected or first empty slot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: 320)
        }
        .sheet(item: $itemEditor) { target in
            itemEditorSheet(for: target)
        }
    }

    // MARK: - My Items

    private var myItems: some View {
        let items = store.customItems(in: bundleID)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                itemEditor = .new
            } label: {
                Label("New Item…", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Make your own ring items")
                        .font(.headline)
                    Text("Give it a name and an icon, then choose what it does: press a shortcut, run a command in Terminal (like flutter run), run a script, open a link, and more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SuggestedActionsList(
                    actions: items,
                    onSelect: { place($0) },
                    onEdit: { index in itemEditor = .myItem(index) },
                    onDelete: { index in store.removeCustomItem(at: index, in: bundleID) }
                )
                Text("Click an item to put it in the selected or first empty slot, or drag it onto a slot. Right-click to edit or delete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func itemEditorSheet(for target: ItemEditorTarget) -> some View {
        switch target {
        case .new:
            RingItemEditor(title: "New Ring Item", item: nil) { item in
                store.addCustomItem(item, in: bundleID)
                place(item)
            }
        case .myItem(let index):
            RingItemEditor(title: "Edit Item", item: store.customItems(in: bundleID)[safeIndex: index]) { item in
                store.replaceCustomItem(at: index, with: item, in: bundleID)
            }
        case .slot(let index):
            RingItemEditor(title: "Edit Slot \(index + 1)", item: resolved.ring[index]) { item in
                store.setRingSlot(index, to: item, in: bundleID)
            }
        }
    }

    private func place(_ action: ActionConfig) {
        if let slot = editingSlot ?? firstEmptySlot {
            store.setRingSlot(slot, to: action, in: bundleID)
        }
    }

    private var firstEmptySlot: Int? {
        (0..<RingConfig.slotCount).first { resolved.ring[$0] == nil }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                sourceBadge
            }
            Spacer()
            Picker("Size", selection: $store.settings.general.ringSize) {
                ForEach(RingSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Button("Clear All") { store.clearRing(in: bundleID) }
                .disabled(resolved.ring.slots.allSatisfy { $0 == nil })
            Button("Reset to Default") { store.resetRing(in: bundleID) }
                .disabled(!store.canResetRing(in: bundleID))
        }
    }

    private var title: String {
        store.settings.appProfile(for: bundleID).map { "Actions Ring – \($0.name)" } ?? "Actions Ring – All Applications"
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch resolved.source {
        case .appProfile:
            Badge(text: "Overrides All Applications", color: .orange)
        case .builtIn(let name):
            Badge(text: "Built-in ring for \(name). Edit to customize.", color: .blue)
        case .global where bundleID != nil:
            Badge(text: "Inherited from All Applications", color: .secondary)
        case .global:
            Text("Apps with a built-in ring (Safari, Chrome, Finder, VS Code, Cursor, Xcode, Zoom, …) use that one instead. Pick an app in the bar above to see or change its ring.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Trigger info

    private var ringTriggers: [TriggerKey] {
        let app = store.settings.appProfile(for: bundleID)?.profile
        return Profile.resolved(global: store.settings.globalProfile, app: app)
            .filter { $0.value.actionID == .actionsRing }
            .map(\.key)
            .sorted { ($0.button, $0.kind.rawValue) < ($1.button, $1.kind.rawValue) }
    }

    @ViewBuilder
    private var triggerInfo: some View {
        let triggers = ringTriggers
        if triggers.isEmpty {
            HStack {
                Label("No button opens the ring yet.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Use Hold Back Button") {
                    store.setBinding(ActionConfig(.actionsRing), for: TriggerKey(button: MouseButtons.back, kind: .hold), in: bundleID)
                }
            }
        } else {
            Label("Opens with: " + triggers.map(\.displayName).joined(separator: ", "), systemImage: "computermouse")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Editor

    private var editor: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) - 8
            let bubble = max(70, diameter * 0.2)
            let radius = diameter / 2 - bubble / 2 - 6
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                    .frame(width: diameter, height: diameter)
                    .position(center)
                VStack(spacing: 2) {
                    Image(systemName: "xmark")
                    Text("Cancel").font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(width: diameter * 0.26, height: diameter * 0.26)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .position(center)

                ForEach(0..<RingConfig.slotCount, id: \.self) { index in
                    slotView(index, size: bubble)
                        .position(RingGeometry.position(ofSlot: index, center: center, radius: radius))
                }
            }
        }
        .frame(minHeight: 360)
    }

    private func slotView(_ index: Int, size: CGFloat) -> some View {
        let action = resolved.ring[index]
        let isTarget = dropTarget == index
        return Button {
            editingSlot = index
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isTarget ? Color.accentColor.opacity(0.35) : (action == nil ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.14)))
                    Circle()
                        .strokeBorder(isTarget || editingSlot == index ? Color.accentColor : Color.primary.opacity(0.2),
                                      style: StrokeStyle(lineWidth: 1.5, dash: action == nil ? [4, 3] : []))
                    Image(systemName: action.map(ActionLibrary.symbol(for:)) ?? "plus")
                        .font(.system(size: size * 0.28))
                        .foregroundStyle(action == nil ? Color.secondary : Color.primary)
                }
                .frame(width: size * 0.62, height: size * 0.62)
                Text(action.map(ActionLibrary.displayName(for:)) ?? "Empty")
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: size * 1.2)
                    .foregroundStyle(action == nil ? .secondary : .primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Slot \(index + 1): \(action.map(ActionLibrary.displayName(for:)) ?? "Empty")")
        .contextMenu {
            Button(action == nil ? "New Item Here…" : "Edit Name, Icon & Action…") { itemEditor = .slot(index) }
            if let action {
                Button("Save to My Items") { store.addCustomItem(action, in: bundleID) }
                Divider()
                Button("Clear Slot") { store.setRingSlot(index, to: nil, in: bundleID) }
            }
        }
        .onDrag { NSItemProvider(object: "slot:\(index)" as NSString) }
        .onDrop(of: [UTType.text], isTargeted: Binding(
            get: { dropTarget == index },
            set: { targeted in dropTarget = targeted ? index : (dropTarget == index ? nil : dropTarget) }
        )) { providers in
            handleDrop(providers, onto: index)
        }
        .popover(isPresented: Binding(
            get: { editingSlot == index },
            set: { if !$0 { editingSlot = nil } }
        ), arrowEdge: .bottom) {
            ActionChooserPanel(
                action: Binding(
                    get: { resolved.ring[index] },
                    set: { store.setRingSlot(index, to: $0, in: bundleID) }
                ),
                exclude: [.actionsRing, .defaultBehavior]
            )
            .frame(width: 360, height: 480)
            .padding(12)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], onto index: Int) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String else { return }
            DispatchQueue.main.async {
                if text.hasPrefix(SuggestedActionsList.dragPrefix),
                   let data = text.dropFirst(SuggestedActionsList.dragPrefix.count).data(using: .utf8),
                   let config = try? JSONDecoder().decode(ActionConfig.self, from: data) {
                    store.setRingSlot(index, to: config, in: bundleID)
                } else if text.hasPrefix("slot:"), let from = Int(text.dropFirst(5)) {
                    if from != index { store.swapRingSlots(from, index, in: bundleID) }
                } else if ActionLibrary.action(ActionID(rawValue: text)) != nil {
                    store.setRingSlot(index, to: ActionConfig(ActionID(rawValue: text)), in: bundleID)
                }
            }
        }
        return true
    }
}

/// An app's own commands (from its built-in preset), ready to drop on the ring.
private struct SuggestedActionsList: View {
    static let dragPrefix = "config:"

    let actions: [ActionConfig]
    let onSelect: (ActionConfig) -> Void
    var onEdit: ((Int) -> Void)?
    var onDelete: ((Int) -> Void)?

    var body: some View {
        List(Array(actions.enumerated()), id: \.offset) { index, action in
            Button { onSelect(action) } label: {
                HStack(spacing: 10) {
                    Image(systemName: ActionLibrary.symbol(for: action))
                        .frame(width: 20)
                        .foregroundStyle(Color.accentColor)
                    Text(ActionLibrary.displayName(for: action))
                    Spacer()
                    if let onEdit {
                        Button { onEdit(index) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("Edit")
                    }
                    if let combo = action.shortcut {
                        Text(combo.displayString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                if let onEdit { Button("Edit…") { onEdit(index) } }
                if let onDelete { Button("Delete", role: .destructive) { onDelete(index) } }
            }
            .onDrag {
                let json = (try? JSONEncoder().encode(action)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                return NSItemProvider(object: (Self.dragPrefix + json) as NSString)
            }
        }
        .listStyle(.inset)
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
