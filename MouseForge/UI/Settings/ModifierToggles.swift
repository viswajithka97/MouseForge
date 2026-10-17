//
//  ModifierToggles.swift
//  MouseForge
//
//  ⌃ ⌥ ⇧ ⌘ toggle buttons for choosing a modifier combination. Keys that
//  are on fill with the accent color so the state is obvious.
//

import SwiftUI

struct ModifierToggles: View {
    @Binding var modifiers: ModifierSet

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ModifierSet.ordered, id: \.rawValue) { key in
                let isOn = modifiers.contains(key)
                Button {
                    if isOn { modifiers.remove(key) } else { modifiers.insert(key) }
                } label: {
                    Text(key.symbols)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 22)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(key.name)
                .accessibilityLabel(key.name)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
