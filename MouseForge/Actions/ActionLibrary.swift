//
//  ActionLibrary.swift
//  MouseForge
//
//  Every action a button can be bound to, grouped by category. Shortcut
//  based actions use the macOS default shortcuts; if the user changed one
//  in System Settings ▸ Keyboard ▸ Keyboard Shortcuts, the action follows
//  the default, not the customised key.
//

import Carbon.HIToolbox
import Foundation

extension ActionID {
    // Navigation
    static let back: ActionID = "back"
    static let forward: ActionID = "forward"
    static let middleClick: ActionID = "middleClick"
    static let nextTab: ActionID = "nextTab"
    static let previousTab: ActionID = "previousTab"
    static let newTab: ActionID = "newTab"
    static let closeTab: ActionID = "closeTab"
    static let reopenTab: ActionID = "reopenTab"
    static let scrollToTop: ActionID = "scrollToTop"
    static let scrollToBottom: ActionID = "scrollToBottom"
    static let zoomIn: ActionID = "zoomIn"
    static let zoomOut: ActionID = "zoomOut"
    static let zoomReset: ActionID = "zoomReset"
    // Window & desktop
    static let missionControl: ActionID = "missionControl"
    static let appExpose: ActionID = "appExpose"
    static let showDesktop: ActionID = "showDesktop"
    static let launchpad: ActionID = "launchpad"
    static let spaceLeft: ActionID = "spaceLeft"
    static let spaceRight: ActionID = "spaceRight"
    static let minimizeWindow: ActionID = "minimizeWindow"
    static let fullScreen: ActionID = "fullScreen"
    static let closeWindow: ActionID = "closeWindow"
    static let switchApp: ActionID = "switchApp"
    static let hideApp: ActionID = "hideApp"
    // Editing
    static let copy: ActionID = "copy"
    static let paste: ActionID = "paste"
    static let cut: ActionID = "cut"
    static let undo: ActionID = "undo"
    static let redo: ActionID = "redo"
    static let selectAll: ActionID = "selectAll"
    static let find: ActionID = "find"
    static let save: ActionID = "save"
    // Media
    static let playPause: ActionID = "playPause"
    static let nextTrack: ActionID = "nextTrack"
    static let previousTrack: ActionID = "previousTrack"
    static let volumeUp: ActionID = "volumeUp"
    static let volumeDown: ActionID = "volumeDown"
    static let mute: ActionID = "mute"
    static let brightnessUp: ActionID = "brightnessUp"
    static let brightnessDown: ActionID = "brightnessDown"
    // System
    static let screenshotFull: ActionID = "screenshotFull"
    static let screenshotArea: ActionID = "screenshotArea"
    static let screenshotWindow: ActionID = "screenshotWindow"
    static let screenRecording: ActionID = "screenRecording"
    static let lockScreen: ActionID = "lockScreen"
    static let sleepDisplay: ActionID = "sleepDisplay"
    static let spotlight: ActionID = "spotlight"
    static let doNotDisturb: ActionID = "doNotDisturb"
    static let dictation: ActionID = "dictation"
    static let emojiPicker: ActionID = "emojiPicker"
    static let lookUp: ActionID = "lookUp"
    static let smartZoom: ActionID = "smartZoom"
    static let notificationCenter: ActionID = "notificationCenter"
    // Launch
    static let openApp: ActionID = "openApp"
    static let openFile: ActionID = "openFile"
    static let openFolder: ActionID = "openFolder"
    static let openURL: ActionID = "openURL"
    // Custom
    static let keyboardShortcut: ActionID = "keyboardShortcut"
    static let typeText: ActionID = "typeText"
    static let appleScript: ActionID = "appleScript"
    static let shellScript: ActionID = "shellScript"
    static let runInTerminal: ActionID = "runInTerminal"
    static let runShortcut: ActionID = "runShortcut"
    // Special
    static let actionsRing: ActionID = "actionsRing"
    static let smartAction: ActionID = "smartAction"
    static let dpiCycle: ActionID = "dpiCycle"
    static let doNothing: ActionID = "doNothing"
    static let defaultBehavior: ActionID = "defaultBehavior"
}

enum ActionLibrary {
    static let all: [any MouseAction] = [
        // MARK: Navigation
        ShortcutAction(id: .back, name: "Back", symbol: "chevron.backward", category: .navigation,
                       combo: KeyCombo(kVK_ANSI_LeftBracket, .command), keywords: ["previous page", "browser"]),
        ShortcutAction(id: .forward, name: "Forward", symbol: "chevron.forward", category: .navigation,
                       combo: KeyCombo(kVK_ANSI_RightBracket, .command), keywords: ["next page", "browser"]),
        CustomAction(id: .middleClick, name: "Middle Click", symbol: "computermouse", category: .navigation,
                     keywords: ["open link in new tab", "button 3"]) { _ in
            SyntheticEvents.click(button: MouseButtons.middle)
        },
        ShortcutAction(id: .nextTab, name: "Next Tab", symbol: "arrow.right.square", category: .navigation,
                       combo: KeyCombo(kVK_Tab, .control), keywords: ["switch tab"]),
        ShortcutAction(id: .previousTab, name: "Previous Tab", symbol: "arrow.left.square", category: .navigation,
                       combo: KeyCombo(kVK_Tab, [.control, .shift]), keywords: ["switch tab"]),
        ShortcutAction(id: .newTab, name: "New Tab", symbol: "plus.square", category: .navigation,
                       combo: KeyCombo(kVK_ANSI_T, .command)),
        ShortcutAction(id: .closeTab, name: "Close Tab", symbol: "xmark.square", category: .navigation,
                       combo: KeyCombo(kVK_ANSI_W, .command)),
        ShortcutAction(id: .reopenTab, name: "Reopen Closed Tab", symbol: "arrow.uturn.backward.square",
                       category: .navigation, combo: KeyCombo(kVK_ANSI_T, [.shift, .command]), keywords: ["restore", "undo close"]),
        ShortcutAction(id: .scrollToTop, name: "Scroll to Top", symbol: "arrow.up.to.line", category: .navigation,
                       combo: KeyCombo(kVK_Home), keywords: ["home", "beginning"]),
        ShortcutAction(id: .scrollToBottom, name: "Scroll to Bottom", symbol: "arrow.down.to.line", category: .navigation,
                       combo: KeyCombo(kVK_End), keywords: ["end"]),
        ShortcutAction(id: .zoomIn, name: "Zoom In", symbol: "plus.magnifyingglass", category: .navigation,
                       combo: KeyCombo(kVK_ANSI_Equal, .command), keywords: ["bigger", "magnify"]),
        ShortcutAction(id: .zoomOut, name: "Zoom Out", symbol: "minus.magnifyingglass", category: .navigation,
                       combo: KeyCombo(kVK_ANSI_Minus, .command), keywords: ["smaller"]),
        ShortcutAction(id: .zoomReset, name: "Actual Size", symbol: "1.magnifyingglass", category: .navigation,
                       combo: KeyCombo(kVK_ANSI_0, .command), keywords: ["zoom reset", "100%"]),

        // MARK: Window & Desktop
        CustomAction(id: .missionControl, name: "Mission Control", symbol: "rectangle.3.group",
                     category: .windowDesktop, keywords: ["expose", "all windows"]) { _ in SystemControls.missionControl() },
        CustomAction(id: .appExpose, name: "App Exposé", symbol: "rectangle.stack",
                     category: .windowDesktop, keywords: ["application windows"]) { _ in SystemControls.appExpose() },
        CustomAction(id: .showDesktop, name: "Show Desktop", symbol: "menubar.dock.rectangle",
                     category: .windowDesktop) { _ in SystemControls.showDesktop() },
        CustomAction(id: .launchpad, name: "Launchpad / Apps", symbol: "square.grid.3x3",
                     category: .windowDesktop, keywords: ["applications"]) { _ in SystemControls.launchpad() },
        ShortcutAction(id: .spaceLeft, name: "Space Left", symbol: "arrow.left.to.line.compact", category: .windowDesktop,
                       combo: KeyCombo(kVK_LeftArrow, .control), keywords: ["desktop", "switch space", "previous"]),
        ShortcutAction(id: .spaceRight, name: "Space Right", symbol: "arrow.right.to.line.compact", category: .windowDesktop,
                       combo: KeyCombo(kVK_RightArrow, .control), keywords: ["desktop", "switch space", "next"]),
        CustomAction(id: .minimizeWindow, name: "Minimize Window", symbol: "minus.square",
                     category: .windowDesktop) { _ in SystemControls.minimizeWindow() },
        CustomAction(id: .fullScreen, name: "Toggle Full Screen", symbol: "arrow.up.left.and.arrow.down.right",
                     category: .windowDesktop) { _ in SystemControls.toggleFullScreen() },
        CustomAction(id: .closeWindow, name: "Close Window", symbol: "xmark.rectangle",
                     category: .windowDesktop) { _ in SystemControls.closeWindow() },
        ShortcutAction(id: .switchApp, name: "Switch to Previous App", symbol: "square.on.square",
                       category: .windowDesktop, combo: KeyCombo(kVK_Tab, .command), keywords: ["command tab", "app switcher"]),
        CustomAction(id: .hideApp, name: "Hide App", symbol: "eye.slash",
                     category: .windowDesktop) { _ in SystemControls.hideFrontmostApp() },

        // MARK: Editing
        ShortcutAction(id: .copy, name: "Copy", symbol: "doc.on.doc", category: .editing, combo: KeyCombo(kVK_ANSI_C, .command)),
        ShortcutAction(id: .paste, name: "Paste", symbol: "doc.on.clipboard", category: .editing, combo: KeyCombo(kVK_ANSI_V, .command)),
        ShortcutAction(id: .cut, name: "Cut", symbol: "scissors", category: .editing, combo: KeyCombo(kVK_ANSI_X, .command)),
        ShortcutAction(id: .undo, name: "Undo", symbol: "arrow.uturn.backward", category: .editing, combo: KeyCombo(kVK_ANSI_Z, .command)),
        ShortcutAction(id: .redo, name: "Redo", symbol: "arrow.uturn.forward", category: .editing,
                       combo: KeyCombo(kVK_ANSI_Z, [.shift, .command])),
        ShortcutAction(id: .selectAll, name: "Select All", symbol: "rectangle.dashed", category: .editing,
                       combo: KeyCombo(kVK_ANSI_A, .command)),
        ShortcutAction(id: .find, name: "Find", symbol: "magnifyingglass", category: .editing,
                       combo: KeyCombo(kVK_ANSI_F, .command), keywords: ["search"]),
        ShortcutAction(id: .save, name: "Save", symbol: "square.and.arrow.down", category: .editing,
                       combo: KeyCombo(kVK_ANSI_S, .command)),

        // MARK: Media
        MediaKeyAction(id: .playPause, name: "Play / Pause", symbol: "playpause.fill", key: .play, keywords: ["music"]),
        MediaKeyAction(id: .nextTrack, name: "Next Track", symbol: "forward.fill", key: .next, keywords: ["skip", "music"]),
        MediaKeyAction(id: .previousTrack, name: "Previous Track", symbol: "backward.fill", key: .previous, keywords: ["music"]),
        MediaKeyAction(id: .volumeUp, name: "Volume Up", symbol: "speaker.wave.3.fill", key: .volumeUp, keywords: ["sound", "louder"]),
        MediaKeyAction(id: .volumeDown, name: "Volume Down", symbol: "speaker.wave.1.fill", key: .volumeDown, keywords: ["sound", "quieter"]),
        MediaKeyAction(id: .mute, name: "Mute", symbol: "speaker.slash.fill", key: .mute, keywords: ["sound"]),
        MediaKeyAction(id: .brightnessUp, name: "Brightness Up", symbol: "sun.max.fill", key: .brightnessUp, keywords: ["display", "screen"]),
        MediaKeyAction(id: .brightnessDown, name: "Brightness Down", symbol: "sun.min.fill", key: .brightnessDown, keywords: ["display", "screen"]),

        // MARK: System
        ShortcutAction(id: .screenshotFull, name: "Screenshot (Full Screen)", symbol: "camera.viewfinder", category: .system,
                       combo: KeyCombo(kVK_ANSI_3, [.shift, .command]), keywords: ["capture", "screen shot"]),
        ShortcutAction(id: .screenshotArea, name: "Screenshot (Area)", symbol: "viewfinder", category: .system,
                       combo: KeyCombo(kVK_ANSI_4, [.shift, .command]), keywords: ["capture", "selection", "screen shot"]),
        CustomAction(id: .screenshotWindow, name: "Screenshot (Window)", symbol: "macwindow", category: .system,
                     keywords: ["capture", "screen shot"]) { _ in
            // ⇧⌘4, then Space switches the crosshair to window mode.
            SyntheticEvents.press(KeyCombo(kVK_ANSI_4, [.shift, .command]))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
                SyntheticEvents.press(KeyCombo(kVK_Space))
            }
        },
        ShortcutAction(id: .screenRecording, name: "Screen Recording", symbol: "record.circle", category: .system,
                       combo: KeyCombo(kVK_ANSI_5, [.shift, .command]), keywords: ["video", "capture", "screenshot toolbar"]),
        ShortcutAction(id: .lockScreen, name: "Lock Screen", symbol: "lock.fill", category: .system,
                       combo: KeyCombo(kVK_ANSI_Q, [.control, .command])),
        CustomAction(id: .sleepDisplay, name: "Sleep Display", symbol: "moon.zzz.fill", category: .system,
                     keywords: ["screen off"]) { _ in SystemControls.sleepDisplay() },
        ShortcutAction(id: .spotlight, name: "Spotlight", symbol: "magnifyingglass.circle", category: .system,
                       combo: KeyCombo(kVK_Space, .command), keywords: ["search"]),
        // The next two post the key codes of the dedicated keys on recent
        // Apple keyboards (F6 moon key, F5 microphone key). Undocumented.
        CustomAction(id: .doNotDisturb, name: "Do Not Disturb", symbol: "moon.fill", category: .system,
                     keywords: ["focus", "dnd"]) { _ in
            SyntheticEvents.postKey(178, down: true, flags: [])
            SyntheticEvents.postKey(178, down: false, flags: [])
        },
        CustomAction(id: .dictation, name: "Dictation", symbol: "mic.fill", category: .system,
                     keywords: ["voice", "speech"]) { _ in
            SyntheticEvents.postKey(176, down: true, flags: [])
            SyntheticEvents.postKey(176, down: false, flags: [])
        },
        ShortcutAction(id: .emojiPicker, name: "Emoji & Symbols", symbol: "face.smiling", category: .system,
                       combo: KeyCombo(kVK_Space, [.control, .command]), keywords: ["character viewer"]),
        ShortcutAction(id: .lookUp, name: "Look Up", symbol: "character.book.closed", category: .system,
                       combo: KeyCombo(kVK_ANSI_D, [.control, .command]), keywords: ["dictionary", "define", "quick look"]),
        CustomAction(id: .smartZoom, name: "Smart Zoom", symbol: "plus.magnifyingglass", category: .system,
                     keywords: ["magnify"]) { _ in SyntheticEvents.smartZoom() },
        CustomAction(id: .notificationCenter, name: "Notification Center", symbol: "bell.badge", category: .system,
                     keywords: ["widgets"]) { _ in SystemControls.notificationCenter() },

        // MARK: Launch
        CustomAction(id: .openApp, name: "Open App", symbol: "app.badge", category: .launch,
                     parameter: .application, keywords: ["launch"]) { config in
            guard let path = config.text, !path.isEmpty else { return SystemControls.beep() }
            SystemControls.openApplication(atPath: path)
        },
        CustomAction(id: .openFile, name: "Open File", symbol: "doc", category: .launch,
                     parameter: .file) { config in SystemControls.open(path: config.text) },
        CustomAction(id: .openFolder, name: "Open Folder", symbol: "folder", category: .launch,
                     parameter: .folder) { config in SystemControls.open(path: config.text) },
        CustomAction(id: .openURL, name: "Open URL", symbol: "link", category: .launch,
                     parameter: .url, keywords: ["website", "web", "link"]) { config in SystemControls.open(urlString: config.text) },

        // MARK: Custom
        CustomAction(id: .keyboardShortcut, name: "Keyboard Shortcut", symbol: "keyboard", category: .custom,
                     parameter: .shortcut, keywords: ["hotkey", "key"]) { config in
            guard let combo = config.shortcut else { return SystemControls.beep() }
            SyntheticEvents.press(combo)
        },
        CustomAction(id: .typeText, name: "Type Text", symbol: "text.cursor", category: .custom,
                     parameter: .text(prompt: "Text to type", multiline: true), keywords: ["snippet", "paste text"]) { config in
            guard let text = config.text, !text.isEmpty else { return SystemControls.beep() }
            SyntheticEvents.type(text)
        },
        CustomAction(id: .appleScript, name: "AppleScript", symbol: "applescript", category: .custom,
                     parameter: .text(prompt: "AppleScript source", multiline: true), keywords: ["script", "automation"]) { config in
            SystemControls.runAppleScript(config.text)
        },
        CustomAction(id: .shellScript, name: "Shell Script", symbol: "terminal", category: .custom,
                     parameter: .text(prompt: "Shell command (runs in zsh)", multiline: true), keywords: ["bash", "zsh", "command"]) { config in
            SystemControls.runShellScript(config.text)
        },
        CustomAction(id: .runInTerminal, name: "Run in Terminal", symbol: "apple.terminal", category: .custom,
                     parameter: .text(prompt: "Command, e.g. cd ~/Projects/my_app && flutter run", multiline: true),
                     keywords: ["terminal", "command", "flutter", "npm", "run", "build"]) { config in
            SystemControls.runInTerminal(config.text)
        },
        CustomAction(id: .runShortcut, name: "Run Shortcut", symbol: "square.2.layers.3d", category: .custom,
                     parameter: .text(prompt: "Shortcut name, exactly as in Shortcuts.app", multiline: false),
                     keywords: ["shortcuts app", "automation"]) { config in
            SystemControls.runShortcut(named: config.text)
        },

        // MARK: Special
        CustomAction(id: .actionsRing, name: "Actions Ring", symbol: "circle.circle", category: .special,
                     keywords: ["radial", "menu", "pie"]) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ActionsRingController.shared.openSticky() }
            }
        },
        CustomAction(id: .smartAction, name: "Smart Action", symbol: "wand.and.stars", category: .special,
                     parameter: .smartAction, keywords: ["macro", "sequence", "steps"]) { config in
            guard let smartAction = SmartActionRegistry.shared.smartAction(for: config) else { return SystemControls.beep() }
            SmartActionRunner.shared.run(smartAction)
        },
        CustomAction(id: .dpiCycle, name: "Cycle DPI", symbol: "gauge.with.dots.needle.33percent", category: .special,
                     keywords: ["sensitivity", "logitech", "speed"]) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AppState.shared.devices.cycleDPI() }
            }
        },
        CustomAction(id: .doNothing, name: "Do Nothing", symbol: "nosign", category: .special,
                     keywords: ["disable", "block", "ignore"]) { _ in },
        CustomAction(id: .defaultBehavior, name: "Default Behavior", symbol: "arrow.uturn.left.circle", category: .special,
                     keywords: ["original", "normal", "native"]) { _ in },
    ]

    private static let byID: [ActionID: any MouseAction] = Dictionary(
        all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
    )

    static func action(_ id: ActionID) -> (any MouseAction)? {
        byID[id]
    }

    /// Search results grouped by category, in library order.
    static func grouped(matching query: String) -> [(category: ActionCategory, actions: [any MouseAction])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return ActionCategory.allCases.compactMap { category in
            let actions = all.filter { $0.category == category && $0.matches(trimmed) }
            return actions.isEmpty ? nil : (category, actions)
        }
    }

    /// e.g. "Open Safari", "Shortcut ⇧⌘T", "Back".
    static func displayName(for config: ActionConfig) -> String {
        if let label = config.label?.trimmingCharacters(in: .whitespaces), !label.isEmpty { return label }
        guard let action = action(config.actionID) else { return "Unknown Action" }
        let text = config.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch action.parameter {
        case .shortcut:
            return config.shortcut.map { "Shortcut \($0.displayString)" } ?? action.name
        case .application, .file, .folder:
            guard !text.isEmpty else { return action.name }
            let item = (URL(fileURLWithPath: text).lastPathComponent as NSString).deletingPathExtension
            return "Open \(item)"
        case .url:
            return text.isEmpty ? action.name : "Open \(text)"
        case .text(_, let multiline):
            guard !text.isEmpty, !multiline else { return action.name }
            return "\(action.name): \(text)"
        case .smartAction:
            guard config.text?.isEmpty == false else { return action.name }
            return SmartActionRegistry.shared.smartAction(for: config)?.name ?? "Missing Smart Action"
        case .none:
            return action.name
        }
    }

    static func symbol(for config: ActionConfig) -> String {
        if let symbol = config.symbol, !symbol.isEmpty { return symbol }
        if config.actionID == .smartAction, let smartAction = SmartActionRegistry.shared.smartAction(for: config) {
            return smartAction.symbol
        }
        return action(config.actionID)?.symbol ?? "questionmark.circle"
    }
}

/// Runs actions off the event-tap thread, one at a time, in order.
final class ActionExecutor: @unchecked Sendable {
    static let shared = ActionExecutor()

    private let queue = DispatchQueue(label: "MouseForge.Actions", qos: .userInitiated)

    func perform(_ config: ActionConfig) {
        guard let action = ActionLibrary.action(config.actionID) else { return }
        queue.async { action.perform(config) }
    }
}
