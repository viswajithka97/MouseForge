//
//  StatusHUD.swift
//  MouseForge
//
//  A small floating badge shown for a moment (kill switch, DPI change, …),
//  over any app and Space.
//

import AppKit
import SwiftUI

@MainActor
enum StatusHUD {
    private static var panel: NSPanel?
    private static var hideWorkItem: DispatchWorkItem?

    static func show(symbol: String, color: Color = .accentColor, title: String, subtitle: String = "") {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: HUDView(symbol: symbol, color: color, title: title, subtitle: subtitle))

        let size = NSSize(width: 280, height: 64)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 120, width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { panel.orderOut(nil) }
            })
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private struct HUDView: View {
        let symbol: String
        let color: Color
        let title: String
        let subtitle: String

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectBackground().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
        }
    }
}

/// The ⌃⌥⌘M kill switch badge.
@MainActor
enum KillSwitchHUD {
    static func show(remappingEnabled enabled: Bool) {
        StatusHUD.show(
            symbol: enabled ? "computermouse.fill" : "pause.circle.fill",
            color: enabled ? .accentColor : .orange,
            title: enabled ? "Remapping On" : "Remapping Off",
            subtitle: "⌃⌥⌘M toggles"
        )
    }
}
