//
//  TestAreaView.swift
//  MouseForge
//
//  A live test area: click, hold, gesture, and scroll on the pad and see
//  both what MouseForge recognized and what an app actually receives.
//  While open, it can pretend a chosen app profile is active (normally the
//  Settings window itself would be the frontmost app).
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class TestAreaModel: ObservableObject {
    @Published private(set) var recognized: [ActivityRecord] = []
    @Published private(set) var received: [ActivityRecord] = []

    private let activity: ActivityLog
    private var timer: Timer?
    private var nextID: UInt64 = 0

    init(activity: ActivityLog) {
        self.activity = activity
    }

    func start() {
        activity.isCapturing = true
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activity.isCapturing = false
    }

    func clear() {
        recognized.removeAll()
        received.removeAll()
    }

    /// Something the pad itself received (i.e. what any app would see).
    func appReceived(symbol: String, _ title: String, _ detail: String = "") {
        nextID += 1
        received.insert(ActivityRecord(id: nextID, time: Date(), symbol: symbol, title: title, detail: detail), at: 0)
        if received.count > 60 { received.removeLast(received.count - 60) }
    }

    private func poll() {
        let new = activity.drain()
        guard !new.isEmpty else { return }
        recognized.insert(contentsOf: new.reversed(), at: 0)
        if recognized.count > 60 { recognized.removeLast(recognized.count - 60) }
    }
}

struct TestAreaView: View {
    @ObservedObject var state: AppState
    @StateObject var model: TestAreaModel
    let done: () -> Void

    @State private var profileChoice: String = TestAreaView.globalChoice

    private static let globalChoice = "\u{0}global"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Test Area").font(.title2.bold())
                Spacer()
                Picker("Use profile", selection: $profileChoice) {
                    Text("All Applications").tag(Self.globalChoice)
                    ForEach(state.store.settings.appProfiles) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                .frame(width: 260)
                Button("Clear") { model.clear() }
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            Text("Click, double-click, hold, drag, gesture, or scroll on the pad. Left: what MouseForge did. Right: what an app receives.")
                .foregroundStyle(.secondary)

            if state.tapStatus != .running || !state.isEnabled {
                Label(
                    state.tapStatus != .running
                        ? "MouseForge isn't intercepting input yet: Accessibility permission is missing, so nothing is remapped. The right column still shows raw events."
                        : "Remapping is paused (⌃⌥⌘M or the menu), so nothing is remapped.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                TestPad(model: model)
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "cursorarrow.click.2").font(.system(size: 34, weight: .light))
                            Text("Test pad").font(.headline)
                            Text("Scroll here too").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))

                RecordList(title: "MouseForge recognized", records: model.recognized)
                RecordList(title: "App received", records: model.received)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 520)
        .onAppear {
            model.start()
            DispatchQueue.main.async { applyProfile() }
        }
        .onDisappear {
            model.stop()
            DispatchQueue.main.async { state.profiles.testOverride = nil }
        }
        .onChange(of: profileChoice) { _ in applyProfile() }
    }

    private func applyProfile() {
        state.profiles.testOverride = .some(profileChoice == Self.globalChoice ? nil : profileChoice)
    }
}

private struct RecordList: View {
    let title: String
    let records: [ActivityRecord]

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            List(records) { record in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: record.symbol).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.title)
                        if !record.detail.isEmpty {
                            Text(record.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Self.formatter.string(from: record.time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minWidth: 260, maxWidth: .infinity)
    }
}

/// An AppKit view that reports every mouse and scroll event it receives.
private struct TestPad: NSViewRepresentable {
    let model: TestAreaModel

    func makeNSView(context: Context) -> PadView {
        let view = PadView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: PadView, context: Context) {
        nsView.model = model
    }

    final class PadView: NSView {
        weak var model: TestAreaModel?
        private var lastScrollReport = Date.distantPast
        private var scrollTotal = CGPoint.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private func report(_ symbol: String, _ title: String, _ detail: String = "") {
            MainActor.assumeIsolated { model?.appReceived(symbol: symbol, title, detail) }
        }

        private func modifiers(_ event: NSEvent) -> String {
            let set = ModifierSet(event.modifierFlags)
            return set.isEmpty ? "" : set.symbols + " "
        }

        override func mouseDown(with event: NSEvent) {
            report("cursorarrow.click", "\(modifiers(event))Left down", event.clickCount > 1 ? "click #\(event.clickCount)" : "")
        }

        override func rightMouseDown(with event: NSEvent) {
            report("cursorarrow.click", "\(modifiers(event))Right down", event.clickCount > 1 ? "click #\(event.clickCount)" : "")
        }

        override func otherMouseDown(with event: NSEvent) {
            let button = event.buttonNumber + 1
            report("computermouse", "\(modifiers(event))\(MouseButtons.name(button)) down", event.clickCount > 1 ? "click #\(event.clickCount)" : "")
        }

        override func otherMouseUp(with event: NSEvent) {
            report("computermouse", "\(MouseButtons.name(event.buttonNumber + 1)) up")
        }

        override func scrollWheel(with event: NSEvent) {
            scrollTotal.x += event.scrollingDeltaX
            scrollTotal.y += event.scrollingDeltaY
            // Summarize at most ~6 times a second so smooth scrolling doesn't flood the list.
            guard Date().timeIntervalSince(lastScrollReport) > 0.16 || event.phase == .ended else { return }
            lastScrollReport = Date()
            let unit = event.hasPreciseScrollingDeltas ? "px" : "lines"
            let kind = event.hasPreciseScrollingDeltas ? "smooth" : "notched"
            report(
                "scroll",
                String(format: "%@Scroll  y %+.1f  x %+.1f %@", modifiers(event), scrollTotal.y, scrollTotal.x, unit),
                kind + (event.momentumPhase.isEmpty ? "" : ", momentum")
            )
            scrollTotal = .zero
        }

        override func magnify(with event: NSEvent) {
            report("plus.magnifyingglass", String(format: "Zoom %+.2f", event.magnification))
        }

        override func smartMagnify(with event: NSEvent) {
            report("plus.magnifyingglass", "Smart Zoom")
        }

        override func keyDown(with event: NSEvent) {
            report("keyboard", "Key \(KeyCombo(Int(event.keyCode), ModifierSet(event.modifierFlags)).displayString)")
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
    }
}
