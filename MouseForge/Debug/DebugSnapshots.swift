//
//  DebugSnapshots.swift
//  MouseForge
//
//  Development aid (Debug builds only): opens a screen and saves a PNG of
//  it, so UI can be checked from the command line. Environment variables:
//    MF_SNAP_DIR   folder to write snapshots into (required)
//    MF_SECTION    SettingsSection raw value, e.g. "actionsRing"
//    MF_APP        bundle ID to select in the app bar
//    MF_RING=1     also open the Actions Ring and snapshot it
//    MF_DARK=1     force dark appearance
//    MF_SETTINGS_FILE  settings JSON to use instead of the real one
//

#if DEBUG
import AppKit

@MainActor
enum DebugSnapshots {
    /// Snapshot runs never start the event tap or show onboarding.
    static var isActive: Bool { ProcessInfo.processInfo.environment["MF_SNAP_DIR"] != nil }

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["MF_SNAP_DIR"] else { return }
        if env["MF_DARK"] == "1" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        let store = AppState.shared.store
        if store.settings.smartActions.isEmpty {
            store.settings.smartActions = SmartActionTemplates.all.map(SmartActionTemplates.instantiate)
        }
        let section = env["MF_SECTION"].flatMap(SettingsSection.init(rawValue:)) ?? .buttons
        WindowManager.shared.showSettings(section: section, selectedApp: .some(env["MF_APP"].flatMap { $0.isEmpty ? nil : $0 }))
        // A covered window isn't drawn, so float it above everything.
        WindowManager.shared.settingsWindowForDebug?.level = .floating
        WindowManager.shared.settingsWindowForDebug?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        WindowManager.shared.settingsWindowForDebug?.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(ProcessInfo.processInfo.environment["MF_DELAY"] ?? "") ?? 4)) {
            if let window = WindowManager.shared.settingsWindowForDebug {
                save(window.contentView?.superview, to: "\(dir)/\(section.rawValue).png")
            }
            if env["MF_RING"] == "1" {
                ActionsRingController.shared.openSticky()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let panels = NSApp.windows.filter { $0 is NSPanel && $0.isVisible }
                    save(panels.last?.contentView, to: "\(dir)/ring.png")
                    AppDelegate.quit()
                }
            } else {
                AppDelegate.quit()
            }
        }
    }

    private static func save(_ view: NSView?, to path: String) {
        guard let view, let window = view.window else { return }
        window.displayIfNeeded()
        // Ask the window server for our own window's pixels (no Screen
        // Recording permission needed for an app's own windows); fall back
        // to drawing the view hierarchy.
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            return
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
