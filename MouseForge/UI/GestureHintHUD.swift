//
//  GestureHintHUD.swift
//  MouseForge
//
//  A brief arrow + action name near the pointer when a gesture fires.
//

import AppKit
import SwiftUI

@MainActor
enum GestureHintHUD {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(direction: GestureDirection, action: ActionConfig?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: HintView(direction: direction, action: action))
        let size = NSSize(width: 220, height: 56)
        let mouse = NSEvent.mouseLocation
        panel.setFrame(NSRect(x: mouse.x - size.width / 2, y: mouse.y + 24, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                 completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }

    private struct HintView: View {
        let direction: GestureDirection
        let action: ActionConfig?

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: direction.arrowSymbol + ".circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                Text(action.map(ActionLibrary.displayName(for:)) ?? "No action")
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .background(VisualEffectBackground().clipShape(Capsule()))
            .frame(maxWidth: .infinity)
        }
    }
}
