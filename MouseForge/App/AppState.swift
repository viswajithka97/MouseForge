//
//  AppState.swift
//  MouseForge
//
//  The app's central object. Owns the permissions tracker, settings, the
//  frontmost-app watcher, the profile manager, and the event tap engine.
//
//  The tap runs whenever macOS allows it. "Enabled" only controls whether
//  buttons are remapped, so the ⌃⌥⌘M kill switch (handled inside the tap)
//  can always switch remapping back on.
//

import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum TapStatus: Equatable {
        case running
        case waitingForPermission
        case failed
    }

    let permissions = PermissionsManager()
    let engine = EventTapEngine()
    let store: SettingsStore = {
        #if DEBUG
        // Snapshot runs use their own settings file, never the user's.
        if let path = ProcessInfo.processInfo.environment["MF_SETTINGS_FILE"] {
            return SettingsStore(fileURL: URL(fileURLWithPath: path))
        }
        #endif
        return SettingsStore()
    }()
    let appWatcher = AppWatcher()
    let profiles: ProfileManager
    let pointer = PointerEngine()
    let devices = DeviceManager()
    let logitech: LogitechIntegration
    let loginItem = LoginItem()

    @Published private(set) var tapStatus: TapStatus = .waitingForPermission

    /// Every button that can be configured, including Logitech controls
    /// (like the gesture button) on connected devices.
    var configurableButtons: [MouseButtonNumber] {
        let logitech = devices.logitechDevices
            .flatMap(\.controls)
            .filter { $0.isDivertable && !$0.isStandardButton }
            .map { LogitechButtons.buttonNumber(for: $0.cid) }
        let bound = LogitechIntegration.boundControls(in: store.settings).map(LogitechButtons.buttonNumber(for:))
        return store.configurableButtons(hardwareButtons: devices.detectedButtonCount) + Array(Set(logitech + bound)).sorted()
    }

    /// Remapping on/off (menu toggle and kill switch). Saved in settings.
    var isEnabled: Bool {
        get { store.settings.general.remappingEnabled }
        set { store.settings.general.remappingEnabled = newValue }
    }

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        profiles = ProfileManager(store: store, watcher: appWatcher, engine: engine)
        logitech = LogitechIntegration(devices: devices, store: store, engine: engine)

        // Views that observe AppState also need to refresh when settings change.
        // Forwarded on the next main-loop turn: re-publishing synchronously
        // could happen while SwiftUI is mid-update (a runtime warning).
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        devices.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        store.$settings
            .map(\.smartActions)
            .removeDuplicates()
            .sink { SmartActionRegistry.shared.update($0) }
            .store(in: &cancellables)

        store.$settings
            .map(\.pointer)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.pointer.apply($0) }
            .store(in: &cancellables)

        engine.setKnownExtraButtons(store.settings.knownExtraButtons)
        engine.onNewExtraButton = { [weak self] button in
            self?.store.addKnownExtraButton(button)
        }
        ActionsRingController.shared.configure(engine: engine, store: store, profiles: profiles)
        ActionsRingController.shared.onSlotHover = { [weak self] _ in self?.logitech.hapticTick() }
        engine.onRingInput = { input in
            ActionsRingController.shared.handle(input)
        }
        engine.onGesture = { [weak self] direction, action, showHint in
            if showHint { GestureHintHUD.show(direction: direction, action: action) }
            self?.logitech.hapticTick()
        }
        engine.onKillSwitch = { [weak self] enabled in
            if !enabled {
                ActionsRingController.shared.close()
                SmartActionRunner.shared.cancelAll()
            }
            self?.isEnabled = enabled
            KillSwitchHUD.show(remappingEnabled: enabled)
        }

        permissions.$accessibilityGranted
            .removeDuplicates()
            .sink { [weak self] _ in
                // $accessibilityGranted fires before the property updates,
                // so defer until the new value is visible.
                DispatchQueue.main.async { self?.updateTap() }
            }
            .store(in: &cancellables)

        // Permissions can be revoked while we're running; re-check whenever
        // one of our windows comes to the front.
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.permissions.refresh() }
            .store(in: &cancellables)
    }

    func launch() {
        #if DEBUG
        if DebugSnapshots.isActive { return }
        #endif
        devices.start()
        updateTap()
        // Only when something is really missing; checks never prompt.
        if !permissions.allGranted {
            WindowManager.shared.showOnboarding()
        }
    }

    func shutdown() {
        engine.stop()
        ActionsRingController.shared.close()
        pointer.restoreAll()
        logitech.releaseAll()
        store.flush()
    }

    private func updateTap() {
        guard permissions.accessibilityGranted else {
            engine.stop()
            ActionsRingController.shared.close()
            tapStatus = .waitingForPermission
            return
        }
        do {
            try engine.start()
            tapStatus = .running
            tapRetries = 0
        } catch {
            tapStatus = .failed
            scheduleTapRetry()
        }
    }

    /// Right after the user flips the Accessibility switch, macOS can take
    /// a moment before it lets us create the tap. Retry a few times; if it
    /// still fails, onboarding offers a relaunch.
    private var tapRetries = 0

    private func scheduleTapRetry() {
        guard tapRetries < 5 else { return }
        tapRetries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.tapStatus == .failed else { return }
            self.permissions.refresh()
            self.updateTap()
        }
    }

    /// Try again after the user fixes something in System Settings.
    func retryTap() {
        tapRetries = 0
        permissions.refresh()
        engine.stop()
        updateTap()
    }
}
