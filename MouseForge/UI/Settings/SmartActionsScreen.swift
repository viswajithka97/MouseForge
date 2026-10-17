//
//  SmartActionsScreen.swift
//  MouseForge
//
//  Create and edit Smart Actions (macros). Steps can be reordered by
//  dragging; a step is a library action or a pause.
//

import SwiftUI

struct SmartActionsScreen: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 250)
            Divider()
            if let index = store.settings.smartActions.firstIndex(where: { $0.id == selection }) {
                SmartActionEditor(store: store, smartAction: $store.settings.smartActions[index])
                    .id(store.settings.smartActions[index].id)
            } else {
                emptyState
            }
        }
        .onAppear {
            if selection == nil { selection = store.settings.smartActions.first?.id }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.settings.smartActions) { smartAction in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(smartAction.name)
                            Text(smartAction.steps.count == 1 ? "1 step" : "\(smartAction.steps.count) steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: smartAction.symbol)
                    }
                    .tag(smartAction.id)
                    .contextMenu {
                        Button("Duplicate") { selection = store.duplicateSmartAction(smartAction.id) }
                        Button("Delete", role: .destructive) { delete(smartAction.id) }
                    }
                }
                .onMove { store.settings.smartActions.move(fromOffsets: $0, toOffset: $1) }
            }
            Divider()
            HStack(spacing: 4) {
                Menu {
                    Button("New Smart Action") {
                        selection = store.addSmartAction(SmartAction(name: "New Smart Action", steps: [.action(ActionConfig(.copy))]))
                    }
                    Divider()
                    Section("Templates") {
                        ForEach(SmartActionTemplates.all, id: \.name) { template in
                            Button {
                                selection = store.addSmartAction(SmartActionTemplates.instantiate(template))
                            } label: {
                                Label(template.name, systemImage: template.symbol)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("New Smart Action")

                Button {
                    if let selection { delete(selection) }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help("Delete Smart Action")
                Spacer()
            }
            .padding(8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Smart Actions run several steps with one click, like “open Notes, wait a second, start a new note, type a heading.”")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Menu("Start from a Template") {
                ForEach(SmartActionTemplates.all, id: \.name) { template in
                    Button {
                        selection = store.addSmartAction(SmartActionTemplates.instantiate(template))
                    } label: {
                        Label(template.name, systemImage: template.symbol)
                    }
                }
            }
            .fixedSize()
            Button("New Empty Smart Action") {
                selection = store.addSmartAction(SmartAction(name: "New Smart Action"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func delete(_ id: UUID) {
        let index = store.settings.smartActions.firstIndex { $0.id == id }
        store.removeSmartAction(id)
        if let index, !store.settings.smartActions.isEmpty {
            selection = store.settings.smartActions[min(index, store.settings.smartActions.count - 1)].id
        } else {
            selection = nil
        }
    }
}

private struct SmartActionEditor: View {
    @ObservedObject var store: SettingsStore
    @Binding var smartAction: SmartAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(SmartAction.symbolChoices, id: \.self) { symbol in
                        Button {
                            smartAction.symbol = symbol
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                } label: {
                    Image(systemName: smartAction.symbol)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Icon")
                TextField("Name", text: $smartAction.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                Button {
                    SmartActionRunner.shared.run(smartAction)
                } label: {
                    Label("Test Run", systemImage: "play.fill")
                }
                .disabled(smartAction.steps.isEmpty)
                .help("Runs the steps now. Keystrokes go to this window, so switch apps first or use a step that opens one.")
            }

            List {
                ForEach(Array(smartAction.steps.enumerated()), id: \.element.id) { index, step in
                    StepRow(
                        number: index + 1,
                        step: $smartAction.steps[index],
                        ownID: smartAction.id
                    ) {
                        smartAction.steps.remove(at: index)
                    }
                }
                .onMove { smartAction.steps.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if smartAction.steps.isEmpty {
                    Text("No steps yet. Add one below.").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text("Add:").foregroundStyle(.secondary)
                addButton("Action", "bolt") { .action(ActionConfig(.copy)) }
                addButton("Wait", "hourglass") { .delay(1) }
                addButton("Type Text", "text.cursor") { .action(ActionConfig(.typeText, text: "")) }
                addButton("Open App", "app.badge") { .action(ActionConfig(.openApp)) }
                addButton("Open URL", "link") { .action(ActionConfig(.openURL, text: "https://")) }
                addButton("Open File", "doc") { .action(ActionConfig(.openFile)) }
            }
            .controlSize(.small)

            let usages = store.usages(of: smartAction.id)
            Text(usages.isEmpty
                 ? "Not assigned yet. Choose “Smart Action” for a button, gesture, or ring slot to run it."
                 : "Used by: " + usages.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
    }

    private func addButton(_ title: String, _ symbol: String, _ make: @escaping () -> SmartStep) -> some View {
        Button {
            smartAction.steps.append(make())
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

private struct StepRow: View {
    let number: Int
    @Binding var step: SmartStep
    let ownID: UUID
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18)
            switch step.kind {
            case .delay:
                Image(systemName: "hourglass").frame(width: 20)
                Text("Wait")
                TextField("Seconds", value: Binding(
                    get: { step.delay ?? 1 },
                    set: { step.delay = $0.clamped(to: SmartStep.delayRange) }
                ), format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                Stepper("", value: Binding(
                    get: { step.delay ?? 1 },
                    set: { step.delay = $0.clamped(to: SmartStep.delayRange) }
                ), in: SmartStep.delayRange, step: 0.25)
                .labelsHidden()
                Text("seconds").foregroundStyle(.secondary)
            case .action:
                ActionChooser(
                    action: Binding(get: { step.action }, set: { step.action = $0 }),
                    placeholder: "Choose Action…",
                    exclude: [.actionsRing, .defaultBehavior],
                    allowsClear: false
                )
                if step.action?.actionID == .smartAction, step.action?.text == ownID.uuidString {
                    Label("Runs itself", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .help("A Smart Action that runs itself stops after a few repeats.")
                }
            }
            Spacer()
            Button(action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove step")
        }
        .padding(.vertical, 2)
    }
}
