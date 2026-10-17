//
//  SystemControls.swift
//  MouseForge
//
//  The system-level work behind actions that aren't plain keyboard
//  shortcuts: Dock features, window control via the Accessibility API,
//  launching things, and running scripts.
//
//  PRIVATE API: `CoreDockSendNotification` (looked up at runtime, so the
//  app still launches if Apple removes it; each use has a public fallback).
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

enum SystemControls {
    private static let logger = Logger(subsystem: "com.mouse.forge.MouseForge", category: "Actions")

    // MARK: - Dock (Mission Control, App Exposé, Show Desktop, Launchpad)

    private typealias CoreDockSendNotificationFn = @convention(c) (CFString, Int32) -> Void

    private static let coreDockSendNotification: CoreDockSendNotificationFn? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "CoreDockSendNotification")
        else { return nil }
        return unsafeBitCast(symbol, to: CoreDockSendNotificationFn.self)
    }()

    /// Returns false if the private function isn't available.
    @discardableResult
    static func sendDockNotification(_ name: String) -> Bool {
        guard let send = coreDockSendNotification else { return false }
        send(name as CFString, 0)
        return true
    }

    static func missionControl() {
        if !sendDockNotification("com.apple.expose.awake") {
            openApplication(atPath: "/System/Applications/Mission Control.app")
        }
    }

    static func appExpose() {
        if !sendDockNotification("com.apple.expose.front.awake") {
            SyntheticEvents.press(KeyCombo(kVK_DownArrow, .control))
        }
    }

    static func showDesktop() {
        if !sendDockNotification("com.apple.showdesktop.awake") {
            SyntheticEvents.press(KeyCombo(kVK_F11))
        }
    }

    /// macOS 26 replaced Launchpad with the "Apps" app.
    static func launchpad() {
        let launchpad = "/System/Applications/Launchpad.app"
        if FileManager.default.fileExists(atPath: launchpad) {
            if !sendDockNotification("com.apple.launchpad.toggle") {
                openApplication(atPath: launchpad)
            }
        } else {
            openApplication(atPath: "/System/Applications/Apps.app")
        }
    }

    // MARK: - Windows (Accessibility API)

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // A hung app must not hang us.
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    static func minimizeWindow() {
        if let window = focusedWindow(),
           AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
            return
        }
        SyntheticEvents.press(KeyCombo(kVK_ANSI_M, .command))
    }

    static func toggleFullScreen() {
        let attribute = "AXFullScreen" as CFString
        if let window = focusedWindow() {
            var current: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, attribute, &current) == .success,
               let isFull = current as? Bool,
               AXUIElementSetAttributeValue(window, attribute, (!isFull) as CFBoolean) == .success {
                return
            }
        }
        SyntheticEvents.press(KeyCombo(kVK_ANSI_F, [.control, .command]))
    }

    static func closeWindow() {
        if let window = focusedWindow() {
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
               let button, CFGetTypeID(button) == AXUIElementGetTypeID(),
               AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success {
                return
            }
        }
        SyntheticEvents.press(KeyCombo(kVK_ANSI_W, .command))
    }

    static func hideFrontmostApp() {
        NSWorkspace.shared.frontmostApplication?.hide()
    }

    /// Clicks the menu-bar clock (owned by Control Center), which opens
    /// Notification Center. There's no public API for this.
    static func notificationCenter() {
        guard let controlCenter = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        else { return beep() }
        let app = AXUIElementCreateApplication(controlCenter.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)

        var bar: CFTypeRef?
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement]
        else { return beep() }

        for item in items {
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifier)
            if (identifier as? String) == "com.apple.menuextra.clock" {
                AXUIElementPerformAction(item, kAXPressAction as CFString)
                return
            }
        }
        beep()
    }

    // MARK: - Launching

    static func openApplication(atPath path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { logger.error("Couldn't open \(path, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
    }

    static func open(path: String?) {
        guard let path, !path.isEmpty else { return beep() }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return beep() }
        NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
    }

    static func open(urlString: String?) {
        guard var text = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return beep() }
        if !text.contains("://") && !text.hasPrefix("mailto:") { text = "https://" + text }
        guard let url = URL(string: text) else { return beep() }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Scripts

    /// Runs a command without waiting for it (scripts can take any amount
    /// of time). Output is only logged.
    static func run(_ executable: String, arguments: [String], input: String? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        if input != nil { process.standardInput = inputPipe }
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { process in
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                logger.error("\(executable, privacy: .public) exited with \(process.terminationStatus): \(output, privacy: .public)")
            }
        }
        do {
            try process.run()
            if let input {
                inputPipe.fileHandleForWriting.write(Data(input.utf8))
                try? inputPipe.fileHandleForWriting.close()
            }
        } catch {
            logger.error("Couldn't run \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            beep()
        }
    }

    static func runAppleScript(_ source: String?) {
        guard let source, !source.isEmpty else { return beep() }
        // osascript with no file argument reads the script from stdin.
        run("/usr/bin/osascript", arguments: [], input: source)
    }

    static func runShellScript(_ source: String?) {
        guard let source, !source.isEmpty else { return beep() }
        run("/bin/zsh", arguments: ["-c", source])
    }

    /// Opens a new Terminal window and runs the command there, so its
    /// output stays visible and long-running commands (dev servers,
    /// `flutter run`) keep going. macOS asks once to let MouseForge
    /// control Terminal.
    static func runInTerminal(_ command: String?) {
        guard let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return beep() }
        run("/usr/bin/osascript", arguments: [], input: terminalScript(for: command))
    }

    static func terminalScript(for command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
    }

    static func runShortcut(named name: String?) {
        guard let name, !name.isEmpty else { return beep() }
        run("/usr/bin/shortcuts", arguments: ["run", name])
    }

    static func sleepDisplay() {
        run("/usr/bin/pmset", arguments: ["displaysleepnow"])
    }

    static func beep() {
        DispatchQueue.main.async { NSSound.beep() }
    }
}
