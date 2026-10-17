//
//  PointerEngine.swift
//  MouseForge
//
//  Pointer tracking speed and acceleration for mice (never trackpads),
//  using the public IOHIDEventSystemClient / IOHIDServiceClient API to set
//  each mouse's HIDMouseAcceleration property: macOS's tracking-speed /
//  acceleration amount, fixed-point (×65536); -1 turns acceleration off
//  (linear pointer). This is the same value System Settings' "Tracking
//  speed" slider sets (0–3), but MouseForge allows up to 5 and per-mouse.
//  Current macOS doesn't let apps change a mouse's resolution
//  (HIDPointerResolution), so there is no separate speed multiplier.
//  The original value is remembered per mouse and restored when the user
//  switches back to "System" or quits MouseForge.
//

import AppKit
import Combine
import IOKit.hidsystem
import os

@MainActor
final class PointerEngine: ObservableObject {
    struct Mouse: Identifiable, Equatable {
        let id: UInt64
        let name: String
    }

    @Published private(set) var mice: [Mouse] = []

    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var originals: [UInt64: Int?] = [:]
    /// Services that refused a value; not retried (and not logged again).
    private var refused: Set<UInt64> = []
    private var current = PointerSettings()
    private var timer: Timer?
    private let logger = Logger(subsystem: "com.mouse.forge.MouseForge", category: "Pointer")

    static let accelerationKey = "HIDMouseAcceleration" as CFString

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapply() }
        }
    }

    // MARK: - Applying

    func apply(_ settings: PointerSettings) {
        let wasCustom = current.mode == .custom
        current = settings
        if settings.mode == .custom {
            reapply()
            startWatching()
        } else {
            stopWatching()
            if wasCustom { restoreAll() }
            refreshMice()
        }
    }

    /// Re-sends the custom values. macOS resets them when a mouse
    /// reconnects or the System Settings slider moves.
    func reapply() {
        refreshMice()
        guard current.mode == .custom else { return }
        for service in mouseServices() {
            let id = Self.registryID(service)
            if originals[id] == nil {
                originals[id] = .some(Self.intProperty(service, Self.accelerationKey))
            }
            set(service, id, Self.accelerationValue(for: current))
        }
    }

    /// Puts every mouse back the way macOS had it.
    func restoreAll() {
        for service in mouseServices() {
            let id = Self.registryID(service)
            guard let original = originals[id] else { continue }
            let systemAcceleration = Int((UserDefaults.standard.object(forKey: "com.apple.mouse.scaling") as? Double ?? 0.6875) * 65536)
            set(service, id, original ?? systemAcceleration)
        }
        originals.removeAll()
    }

    /// Fixed-point HIDMouseAcceleration for the settings (pure, for tests).
    nonisolated static func accelerationValue(for settings: PointerSettings) -> Int {
        settings.accelerationEnabled
            ? Int((settings.acceleration.clamped(to: PointerSettings.accelerationRange) * 65536).rounded())
            : -65536
    }

    // MARK: - Services

    private func mouseServices() -> [IOHIDServiceClient] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return services.filter { service in
            guard IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0 else { return false }
            let type = IOHIDServiceClientCopyProperty(service, "HIDPointerAccelerationType" as CFString) as? String
            // Trackpads use their own acceleration and are left alone.
            return type != "HIDTrackpadAcceleration"
        }
    }

    private func refreshMice() {
        var seen = Set<UInt64>()
        let list = mouseServices().compactMap { service -> Mouse? in
            let id = Self.registryID(service)
            guard seen.insert(id).inserted else { return nil }
            let name = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String ?? "Mouse"
            return Mouse(id: id, name: name)
        }
        if list != mice { mice = list }
    }

    private func set(_ service: IOHIDServiceClient, _ id: UInt64, _ value: Int) {
        guard !refused.contains(id), Self.intProperty(service, Self.accelerationKey) != value else { return }
        if !IOHIDServiceClientSetProperty(service, Self.accelerationKey, value as CFNumber) {
            refused.insert(id)
            logger.notice("A mouse (service \(id)) doesn't accept pointer acceleration changes")
        }
    }

    private static func intProperty(_ service: IOHIDServiceClient, _ key: CFString) -> Int? {
        (IOHIDServiceClientCopyProperty(service, key) as? NSNumber)?.intValue
    }

    private static func registryID(_ service: IOHIDServiceClient) -> UInt64 {
        (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
    }

    private func startWatching() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapply() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}
