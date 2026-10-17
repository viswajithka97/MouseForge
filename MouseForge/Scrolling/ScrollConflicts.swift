//
//  ScrollConflicts.swift
//  MouseForge
//
//  Other apps that also rewrite mouse scrolling. When one runs at the same
//  time, both change every wheel event and scrolling turns erratic
//  (double smoothing, double speed, reversed twice), so the Scrolling
//  screen warns about it.
//

import AppKit
import Combine

@MainActor
final class ScrollConflicts: ObservableObject {
    /// Names of running apps that change scrolling.
    @Published private(set) var running: [String] = []

    /// Process names of known scroll tools (the part that does the work,
    /// e.g. Mac Mouse Fix's helper, not its settings window).
    static let knownNames: Set<String> = [
        "Mac Mouse Fix Helper", "Mos", "LinearMouse", "Scroll Reverser", "SmoothScroll",
        "Smooze", "Smooze Pro", "SteerMouse", "UnnaturalScrollWheels", "logioptionsplus_agent",
    ]

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func refresh() {
        let names = NSWorkspace.shared.runningApplications
            .compactMap(\.localizedName)
            .filter { Self.knownNames.contains($0) }
        let unique = Array(Set(names)).sorted()
        if unique != running { running = unique }
    }

    static func displayName(_ processName: String) -> String {
        switch processName {
        case "Mac Mouse Fix Helper": return "Mac Mouse Fix"
        case "logioptionsplus_agent": return "Logi Options+"
        default: return processName
        }
    }
}
