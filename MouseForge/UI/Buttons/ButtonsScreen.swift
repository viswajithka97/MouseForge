//
//  ButtonsScreen.swift
//  MouseForge
//
//  The mouse illustration with clickable buttons. Selecting a button
//  slides in the side panel where its triggers are configured.
//

import SwiftUI

struct ButtonsScreen: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var devices: DeviceManager
    /// nil = All Applications.
    let bundleID: String?
    /// Every configurable button, Logitech controls included.
    let buttons: [MouseButtonNumber]
    let openThumbWheel: () -> Void

    @State private var selectedButton: MouseButtonNumber?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack {
                    Text(profileTitle).font(.title3.weight(.semibold))
                    Spacer()
                    Button {
                        WindowManager.shared.showTestArea()
                    } label: {
                        Label("Test Area", systemImage: "cursorarrow.click.2")
                    }
                    .help("Try your buttons, gestures, and scrolling live")
                    Picker("Illustration", selection: $store.settings.general.mouseStyle) {
                        ForEach(MouseStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                MouseIllustration(
                    style: store.settings.general.mouseStyle,
                    gestureButton: gestureButton,
                    selected: selectedButton,
                    marker: marker(for:),
                    describe: describe(_:),
                    onSelect: { selectedButton = $0 },
                    onThumbWheel: openThumbWheel
                )
                .frame(minHeight: 300, maxHeight: .infinity)
                .padding(.bottom, 12)

                buttonChips
                legend
            }
            .padding(20)
            .frame(minWidth: 380, maxWidth: .infinity)

            if let button = selectedButton {
                Divider()
                ButtonSidePanel(store: store, button: button, bundleID: bundleID) {
                    selectedButton = nil
                }
                .frame(width: 400)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedButton)
    }

    private var profileTitle: String {
        store.settings.appProfile(for: bundleID)?.name ?? "All Applications"
    }

    private var allButtons: [MouseButtonNumber] {
        Array(Set([1, 2] + buttons)).sorted()
    }

    /// The connected Logitech gesture button, if any.
    private var gestureButton: MouseButtonNumber? {
        let gesture = LogitechButtons.buttonNumber(for: LogitechButtons.gestureButtonCID)
        return buttons.contains(gesture) ? gesture : nil
    }

    /// Keyboard-accessible way to pick a button, and the only way to reach
    /// buttons 6+ (which aren't in the drawing).
    private var buttonChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allButtons, id: \.self) { button in
                        Button {
                            selectedButton = button
                        } label: {
                            HStack(spacing: 4) {
                                if marker(for: button) == .locked {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                                Text(shortName(button))
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedButton == button ? .accentColor : nil)
                        .accessibilityLabel(MouseButtons.name(button))
                        .accessibilityValue(describe(button))
                    }
                }
            }
            Text("Extra buttons (6 and up) appear here after you press them once; Logitech controls such as the gesture button appear when the mouse is connected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(Circle().fill(Color.accentColor), "Remapped")
            if bundleID != nil {
                legendItem(Circle().fill(Color.orange), "Overrides All Applications")
            }
            legendItem(Image(systemName: "lock.fill").font(.system(size: 9)), "Locked (see General)")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ symbol: some View, _ text: String) -> some View {
        HStack(spacing: 5) {
            symbol.frame(width: 9, height: 9)
            Text(text)
        }
    }

    private func shortName(_ button: MouseButtonNumber) -> String {
        switch button {
        case MouseButtons.left: return "Left"
        case MouseButtons.right: return "Right"
        case MouseButtons.middle: return "Middle"
        case MouseButtons.back: return "Back"
        case MouseButtons.forward: return "Forward"
        default: return LogitechButtons.isVirtual(button) ? MouseButtons.name(button) : "Button \(button)"
        }
    }

    // MARK: - Status

    private func marker(for button: MouseButtonNumber) -> ButtonMarker {
        if MouseButtons.isPrimary(button) && !store.settings.general.allowPrimaryButtonRemap {
            return .locked
        }
        if bundleID != nil, store.ownBindings(in: bundleID).keys.contains(where: { $0.button == button }) {
            return .overridden
        }
        let app = store.settings.appProfile(for: bundleID)?.profile
        let resolved = Profile.resolved(global: store.settings.globalProfile, app: app)
        let remapped = resolved.contains { $0.key.button == button && !$0.value.isDefaultBehavior }
        return remapped ? .remapped : .none
    }

    /// Hover caption: the plain-click action.
    private func describe(_ button: MouseButtonNumber) -> String {
        if marker(for: button) == .locked { return "Locked" }
        let (action, _) = store.binding(for: TriggerKey(button: button, kind: .click), in: bundleID)
        guard let action, !action.isDefaultBehavior else { return "Default behavior" }
        return ActionLibrary.displayName(for: action)
    }
}
