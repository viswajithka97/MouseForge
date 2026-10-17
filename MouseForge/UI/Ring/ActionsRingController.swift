//
//  ActionsRingController.swift
//  MouseForge
//
//  Shows the Actions Ring at the cursor and turns pointer direction into a
//  slot choice. Two ways to use it:
//  - Held: bound to a Hold trigger. Opens at the hold threshold; moving
//    toward a slot and releasing the button picks it.
//  - Sticky: bound to a click (or run from anywhere else). Stays open; the
//    next click picks the slot under the pointer.
//  Esc, a right click, or releasing in the center cancels.
//
//  The overlay is a non-activating panel that ignores the mouse: the event
//  tap captures the clicks and Esc while the ring is open, so the app
//  underneath keeps focus.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class RingViewModel: ObservableObject {
    @Published var slots: [ActionConfig?] = Array(repeating: nil, count: RingConfig.slotCount)
    @Published var hovered: Int?
    @Published var isOpen = false
    @Published var size: RingSize = .medium
    @Published var subtitle = ""
}

@MainActor
final class ActionsRingController {
    static let shared = ActionsRingController()

    let model = RingViewModel()
    /// Called when the pointer moves onto a different slot (haptic tick).
    var onSlotHover: ((Int) -> Void)?

    private weak var engine: EventTapEngine?
    private weak var store: SettingsStore?
    private weak var profiles: ProfileManager?

    private var panel: NSPanel?
    private var center: CGPoint = .zero
    private var mode: EventTapEngine.RingCaptureMode = .none
    private var timer: Timer?
    private var closeWork: DispatchWorkItem?

    var isOpen: Bool { mode != .none }

    private init() {}

    func configure(engine: EventTapEngine, store: SettingsStore, profiles: ProfileManager) {
        self.engine = engine
        self.store = store
        self.profiles = profiles
    }

    // MARK: - Input

    func handle(_ input: EventTapEngine.RingInput) {
        switch input {
        case .heldBegan:
            open(mode: .held)
        case .heldEnded(let cancelled):
            guard mode == .held else { return }
            cancelled ? close() : commit()
        case .escape:
            close()
        case .click(let secondary):
            guard isOpen else { return }
            if secondary || pointerIsFarOutside { close() } else { commit() }
        }
    }

    /// Opens in sticky mode (from a click binding or another action).
    func openSticky() {
        if isOpen { close() } else { open(mode: .sticky) }
    }

    // MARK: - Showing

    private var deadZone: CGFloat { model.size.diameter * 0.15 }

    private var pointerIsFarOutside: Bool {
        let p = NSEvent.mouseLocation
        let distance = hypot(p.x - center.x, p.y - center.y)
        return distance > model.size.diameter / 2 + 80
    }

    private func open(mode: EventTapEngine.RingCaptureMode) {
        guard let store, !isOpen else { return }
        closeWork?.cancel()

        let bundleID = profiles?.effectiveBundleID
        let (ring, source) = store.settings.ring(for: bundleID)
        model.slots = ring.slots
        model.size = store.settings.general.ringSize
        model.hovered = nil
        switch source {
        case .global: model.subtitle = "All Applications"
        case .builtIn(let name): model.subtitle = name
        case .appProfile: model.subtitle = store.settings.appProfile(for: bundleID)?.name ?? ""
        }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let side = model.size.diameter + 40
        let mouse = NSEvent.mouseLocation
        var frame = NSRect(x: mouse.x - side / 2, y: mouse.y - side / 2, width: side, height: side)
        // Keep the whole ring on screen; selection is relative to where it ends up.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            let visible = screen.frame
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - side)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - side)
        }
        panel.setFrame(frame, display: false)
        center = CGPoint(x: frame.midX, y: frame.midY)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        self.mode = mode
        engine?.setRingCapture(mode)
        DispatchQueue.main.async { self.model.isOpen = true }

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateHover() {
        let p = NSEvent.mouseLocation
        let slot = RingGeometry.slot(forOffset: CGVector(dx: p.x - center.x, dy: p.y - center.y), deadZone: deadZone)
        guard slot != model.hovered else { return }
        model.hovered = slot
        if let slot, model.slots[slot] != nil { onSlotHover?(slot) }
    }

    private func commit() {
        updateHover()
        let chosen = model.hovered.flatMap { model.slots[$0] }
        close()
        guard let chosen else { return }
        engine?.activity.record(symbol: "circle.circle", title: "Actions Ring", detail: ActionLibrary.displayName(for: chosen))
        // Let the ring fade first so it isn't in a screenshot, and so
        // focus-sensitive shortcuts reach the app underneath.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            ActionExecutor.shared.perform(chosen)
        }
    }

    func close() {
        guard isOpen else { return }
        mode = .none
        engine?.setRingCapture(.none)
        timer?.invalidate()
        timer = nil
        model.isOpen = false
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: RingView(model: model))
        return panel
    }
}
