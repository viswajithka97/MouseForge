//
//  LogitechIntegration.swift
//  MouseForge
//
//  Connects Logitech devices to the rest of MouseForge:
//  - diverts an extra control (gesture button etc.) only while some
//    profile gives it an action, and turns its presses into virtual button
//    events for the trigger engine;
//  - diverts the thumb wheel only when a profile needs a non-native mode;
//  - plays haptic ticks (MX Master 4) for ring hover and gestures;
//  - gives every control back to the mouse when MouseForge quits.
//

import Combine
import Foundation

@MainActor
final class LogitechIntegration {
    private let devices: DeviceManager
    private let store: SettingsStore
    private let engine: EventTapEngine

    private var pressed: [UUID: Set<UInt16>] = [:]
    private var lastTick = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []

    init(devices: DeviceManager, store: SettingsStore, engine: EventTapEngine) {
        self.devices = devices
        self.store = store
        self.engine = engine

        devices.onDivertedButtons = { [weak self] device, controls in
            self?.handleButtons(device, controls)
        }
        devices.onThumbWheel = { [weak self] device, rotation in
            self?.handleThumbWheel(device, rotation)
        }
        devices.onDevicesChanged = { [weak self] in
            self?.sync()
        }
        store.$settings
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)
    }

    // MARK: - Which controls MouseForge needs

    /// Virtual buttons with an action in any profile.
    nonisolated static func boundControls(in settings: AppSettings) -> Set<UInt16> {
        let profiles = [settings.globalProfile] + settings.appProfiles.map(\.profile)
        var controls = Set<UInt16>()
        for profile in profiles {
            for (trigger, action) in profile.bindings where !action.isDefaultBehavior {
                if let cid = LogitechButtons.controlID(for: trigger.button) { controls.insert(cid) }
            }
        }
        return controls
    }

    /// True if some profile uses the thumb wheel for anything the mouse
    /// can't do natively (plain horizontal scrolling).
    nonisolated static func needsThumbWheel(in settings: AppSettings) -> Bool {
        let wheels = [settings.globalProfile.thumbWheel ?? ThumbWheelSettings()] + settings.appProfiles.compactMap(\.profile.thumbWheel)
        return wheels.contains { $0.mode != .horizontalScroll || $0.invert || $0.speed != 1 }
    }

    /// Controls whose diversion must change: (control, divert?).
    nonisolated static func diversionChanges(for controls: [ControlInfo], settings: AppSettings) -> [(cid: UInt16, divert: Bool)] {
        let bound = boundControls(in: settings)
        return controls
            .filter { $0.isDivertable && !$0.isStandardButton }
            .compactMap { control in
                let want = settings.logitech.divertControls && bound.contains(control.cid)
                return control.diverted == want ? nil : (control.cid, want)
            }
    }

    /// Brings each device's diversion in line with the settings.
    func sync() {
        // Forget presses on devices that went away (release already sent).
        let present = Set(devices.logitechDevices.map(\.id))
        pressed = pressed.filter { present.contains($0.key) }
        let settings = store.settings
        let thumbNeeded = settings.logitech.divertThumbWheel && Self.needsThumbWheel(in: settings)
        for device in devices.logitechDevices {
            for change in Self.diversionChanges(for: device.controls, settings: settings) {
                if !change.divert, pressed[device.id]?.contains(change.cid) == true {
                    // Handing a held control back: its release won't reach us.
                    handleButtons(device, (pressed[device.id] ?? []).subtracting([change.cid]))
                }
                Task { await device.setDiverted(change.cid, change.divert) }
            }
            if let thumb = device.thumbWheel, thumb.diverted != thumbNeeded {
                Task { await device.setThumbWheel(diverted: thumbNeeded, inverted: thumb.inverted) }
            }
        }
    }

    /// Hands every diverted control and the thumb wheel back to the mouse.
    /// Waits briefly so it completes before the app quits.
    func releaseAll() {
        let work: [(HIDPPDevice, [UInt16], Bool)] = devices.logitechDevices.map { device in
            (device.hidpp, device.controls.filter(\.diverted).map(\.cid), device.thumbWheel?.diverted == true)
        }
        guard work.contains(where: { !$0.1.isEmpty || $0.2 }) else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for (hidpp, controls, thumb) in work {
                for cid in controls { try? await hidpp.setDiverted(cid, false) }
                if thumb { try? await hidpp.setThumbWheel(diverted: false, inverted: false) }
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    // MARK: - Events

    private func handleButtons(_ device: LogitechDevice, _ controls: Set<UInt16>) {
        let previous = pressed[device.id] ?? []
        pressed[device.id] = controls
        for cid in controls.subtracting(previous) {
            engine.injectVirtualButton(LogitechButtons.buttonNumber(for: cid), down: true)
        }
        for cid in previous.subtracting(controls) {
            engine.injectVirtualButton(LogitechButtons.buttonNumber(for: cid), down: false)
        }
    }

    private func handleThumbWheel(_ device: LogitechDevice, _ rotation: Int) {
        guard rotation != 0 else { return }
        let resolution = device.thumbWheel?.divertedResolution ?? 120
        engine.injectThumbWheel(notches: Self.notches(rotation: rotation, resolution: resolution))
    }

    /// Thumb-wheel rotation units → wheel "notches" (about 20 per turn).
    nonisolated static func notches(rotation: Int, resolution: Int) -> Double {
        -Double(rotation) / max(Double(resolution) / 20, 1)
    }

    // MARK: - Haptics

    /// A short tick on mice with haptic feedback (Actions Ring hover,
    /// gestures). Silently does nothing elsewhere.
    func hapticTick() {
        guard store.settings.logitech.hapticTicks, Date().timeIntervalSince(lastTick) > 0.04 else { return }
        lastTick = Date()
        for device in devices.logitechDevices {
            guard let haptics = device.haptics, haptics.enabled else { continue }
            let waveform = haptics.waveforms.contains(0) ? 0 : (haptics.waveforms.first ?? 0)
            let hidpp = device.hidpp
            Task.detached { try? await hidpp.playHaptic(waveform) }
        }
    }
}
