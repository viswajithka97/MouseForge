//
//  AppPresets.swift
//  MouseForge
//
//  Built-in suggestions for popular apps: an Actions Ring that is used
//  automatically, and button / gesture bindings the user can apply with
//  one click. Shortcuts are each app's default keyboard shortcuts.
//

import Carbon.HIToolbox
import Foundation

struct AppPreset: Sendable {
    let name: String
    let bundleIDs: [String]
    let ring: RingConfig?
    var bindings: [TriggerKey: ActionConfig] = [:]
    /// More of the app's commands, offered in the ring editor next to the
    /// ring's own slots.
    var extras: [ActionConfig] = []

    /// Everything the ring editor suggests for this app, without repeats.
    var suggestions: [ActionConfig] {
        var seen: Set<String> = []
        return ((ring?.slots.compactMap { $0 } ?? []) + extras).filter {
            seen.insert(ActionLibrary.displayName(for: $0)).inserted
        }
    }
}

enum AppPresetCatalog {
    private static func key(_ code: Int, _ modifiers: ModifierSet = []) -> KeyCombo { KeyCombo(code, modifiers) }
    private static func sc(_ name: String, _ code: Int, _ modifiers: ModifierSet = [], _ symbol: String? = nil) -> ActionConfig {
        .shortcut(name, key(code, modifiers), symbol: symbol ?? symbols[name])
    }

    /// Icons for preset shortcuts, by name.
    private static let symbols: [String: String] = [
        "Refresh": "arrow.clockwise", "Bookmarks": "book", "History": "clock.arrow.circlepath",
        "Downloads": "arrow.down.circle", "Private Window": "eye.slash", "Incognito Window": "eye.slash",
        "New Window": "macwindow.badge.plus", "New Folder": "folder.badge.plus", "Get Info": "info.circle",
        "Quick Look": "eye", "Go to Folder": "arrow.right.circle", "Show Hidden Files": "eye.circle",
        "Move to Trash": "trash", "AirDrop": "dot.radiowaves.left.and.right",
        "Command Palette": "command", "Quick Open": "doc.text.magnifyingglass", "Toggle Sidebar": "sidebar.left",
        "Terminal": "terminal", "Find in Files": "text.magnifyingglass", "Go to Definition": "arrow.turn.down.right",
        "Format Document": "text.alignleft", "Toggle Comment": "number", "Go Back": "chevron.backward",
        "Go Forward": "chevron.forward", "Build": "hammer", "Run": "play.fill", "Stop": "stop.fill",
        "Clean Build Folder": "trash.circle", "Open Quickly": "doc.text.magnifyingglass",
        "Toggle Navigator": "sidebar.left", "Toggle Debug Area": "rectangle.bottomthird.inset.filled",
        "Brush": "paintbrush", "Eraser": "eraser", "Move": "arrow.up.and.down.and.arrow.left.and.right",
        "Lasso": "lasso", "Hand": "hand.raised", "Zoom": "plus.magnifyingglass", "Swap Colors": "arrow.left.arrow.right",
        "New Layer": "square.stack.3d.up.badge.automatic", "Frame": "number.square", "Rectangle": "rectangle",
        "Text": "textformat", "Pen": "pencil.tip", "Comment": "text.bubble", "Component": "puzzlepiece",
        "Group": "square.on.square.dashed", "Auto Layout": "rectangle.split.3x1", "Blade": "scissors",
        "Select": "cursorarrow", "Trim": "arrow.left.and.right", "Blade at Playhead": "scissors.badge.ellipsis",
        "Play / Pause": "playpause.fill", "Mark In": "chevron.left.to.line", "Mark Out": "chevron.right.to.line",
        "Snapping": "link", "Razor": "scissors", "Selection": "cursorarrow", "Ripple Edit": "arrow.left.and.right.square",
        "Add Edit": "scissors.badge.ellipsis", "Ripple Delete": "delete.left", "Previous Frame": "backward.frame",
        "Next Frame": "forward.frame", "Mute / Unmute": "mic.slash", "Video On / Off": "video", "Camera On / Off": "video",
        "Share Screen": "rectangle.on.rectangle", "Chat": "bubble.left.and.bubble.right", "Participants": "person.2",
        "Raise Hand": "hand.raised", "Gallery View": "square.grid.2x2", "Leave Meeting": "phone.down",
        "Leave Call": "phone.down", "Search": "magnifyingglass", "Activity": "bell", "Quick Switcher": "arrow.left.arrow.right.square",
        "Threads": "text.bubble", "Mentions": "at", "All Unreads": "tray.full", "Direct Messages": "envelope",
        "New Message": "square.and.pencil", "Huddle": "headphones", "Bold": "bold", "Italic": "italic",
        "Volume Up": "speaker.wave.3.fill", "Volume Down": "speaker.wave.1.fill", "Like Song": "heart",
        "Shuffle": "shuffle",
        "Start Debugging": "ladybug", "Run Without Debugging": "play.circle", "Stop Debugging": "stop.fill",
        "Restart Debugging": "arrow.clockwise.circle", "Toggle Breakpoint": "largecircle.fill.circle",
        "Step Over": "arrow.uturn.right", "Step Into": "arrow.down.to.line", "Step Out": "arrow.up.to.line",
        "Run and Debug View": "play.rectangle", "Rename Symbol": "pencil", "Quick Fix": "lightbulb",
        "Split Editor": "rectangle.split.2x1", "Source Control": "arrow.triangle.branch",
        "Problems": "exclamationmark.triangle", "Close Editor": "xmark.square", "Save All": "square.and.arrow.down.on.square",
        "AI Chat": "bubble.left.and.bubble.right", "Agent": "sparkles", "Inline Edit": "wand.and.stars",
        "Test": "checkmark.diamond", "Find in Project": "text.magnifyingglass", "Show Library": "plus.square.on.square",
        "Jump to Definition": "arrow.turn.down.right", "Toggle Canvas": "sidebar.right",
        "Toggle Inspectors": "sidebar.right",
    ]

    /// All preset icons, for tests.
    static var allSymbols: [String] { Array(symbols.values) }
    private static func click(_ button: Int) -> TriggerKey { TriggerKey(button: button, kind: .click) }
    private static func hold(_ button: Int) -> TriggerKey { TriggerKey(button: button, kind: .hold) }

    // MARK: Browsers

    private static func browserRing(bookmarks: ActionConfig, history: ActionConfig, downloads: ActionConfig, privateWindow: ActionConfig) -> RingConfig {
        RingConfig([
            ActionConfig(.newTab),
            sc("Refresh", kVK_ANSI_R, .command),
            ActionConfig(.closeTab),
            downloads,
            ActionConfig(.reopenTab),
            history,
            privateWindow,
            bookmarks,
        ])
    }

    private static let browserBindings: [TriggerKey: ActionConfig] = [
        click(MouseButtons.back): ActionConfig(.back),
        click(MouseButtons.forward): ActionConfig(.forward),
        TriggerKey(button: MouseButtons.middle, kind: .doubleClick): ActionConfig(.closeTab),
        hold(MouseButtons.back): ActionConfig(.actionsRing),
        hold(MouseButtons.forward): ActionConfig(.reopenTab),
    ]

    private static let chromeLikeRing = browserRing(
        bookmarks: sc("Bookmarks", kVK_ANSI_B, [.option, .command]),
        history: sc("History", kVK_ANSI_Y, .command),
        downloads: sc("Downloads", kVK_ANSI_J, [.shift, .command]),
        privateWindow: sc("Incognito Window", kVK_ANSI_N, [.shift, .command])
    )

    // MARK: Code editors (VS Code keyboard shortcuts, also used by Cursor)

    private static let debug = (
        start: sc("Start Debugging", kVK_F5),
        runWithoutDebugging: sc("Run Without Debugging", kVK_F5, .control),
        stop: sc("Stop Debugging", kVK_F5, .shift),
        restart: sc("Restart Debugging", kVK_F5, [.shift, .command]),
        breakpoint: sc("Toggle Breakpoint", kVK_F9)
    )

    private static let codeEditorBindings: [TriggerKey: ActionConfig] = [
        click(MouseButtons.back): sc("Go Back", kVK_ANSI_Minus, .control),
        click(MouseButtons.forward): sc("Go Forward", kVK_ANSI_Minus, [.control, .shift]),
        hold(MouseButtons.back): ActionConfig(.actionsRing),
    ]

    private static let codeEditorExtras: [ActionConfig] = [
        sc("Step Over", kVK_F10),
        sc("Step Into", kVK_F11),
        sc("Step Out", kVK_F11, .shift),
        sc("Run and Debug View", kVK_ANSI_D, [.shift, .command]),
        sc("Quick Open", kVK_ANSI_P, .command),
        sc("Go to Definition", kVK_F12),
        sc("Rename Symbol", kVK_F2),
        sc("Quick Fix", kVK_ANSI_Period, .command),
        sc("Find in Files", kVK_ANSI_F, [.shift, .command]),
        sc("Format Document", kVK_ANSI_F, [.shift, .option]),
        sc("Toggle Comment", kVK_ANSI_Slash, .command),
        sc("Toggle Sidebar", kVK_ANSI_B, .command),
        sc("Split Editor", kVK_ANSI_Backslash, .command),
        sc("Source Control", kVK_ANSI_G, [.control, .shift]),
        sc("Problems", kVK_ANSI_M, [.shift, .command]),
        sc("Save All", kVK_ANSI_S, [.option, .command]),
        sc("Close Editor", kVK_ANSI_W, .command),
    ]

    static let all: [AppPreset] = [
        AppPreset(
            name: "Safari", bundleIDs: ["com.apple.Safari", "com.apple.SafariTechnologyPreview"],
            ring: browserRing(
                bookmarks: sc("Bookmarks", kVK_ANSI_1, [.control, .command]),
                history: sc("History", kVK_ANSI_Y, .command),
                downloads: sc("Downloads", kVK_ANSI_L, [.option, .command]),
                privateWindow: sc("Private Window", kVK_ANSI_N, [.shift, .command])
            ),
            bindings: browserBindings
        ),
        AppPreset(
            name: "Google Chrome",
            bundleIDs: ["com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser", "com.microsoft.edgemac",
                        "company.thebrowser.Browser", "company.thebrowser.dia"],
            ring: chromeLikeRing, bindings: browserBindings
        ),
        AppPreset(
            name: "Firefox", bundleIDs: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"],
            ring: browserRing(
                bookmarks: sc("Bookmarks", kVK_ANSI_B, .command),
                history: sc("History", kVK_ANSI_H, [.shift, .command]),
                downloads: sc("Downloads", kVK_ANSI_Y, [.shift, .command]),
                privateWindow: sc("Private Window", kVK_ANSI_P, [.shift, .command])
            ),
            bindings: browserBindings
        ),
        AppPreset(
            name: "Finder", bundleIDs: ["com.apple.finder"],
            ring: RingConfig([
                sc("New Window", kVK_ANSI_N, .command),
                sc("New Folder", kVK_ANSI_N, [.shift, .command]),
                sc("Get Info", kVK_ANSI_I, .command),
                sc("Quick Look", kVK_Space),
                sc("Go to Folder", kVK_ANSI_G, [.shift, .command]),
                sc("Show Hidden Files", kVK_ANSI_Period, [.shift, .command]),
                sc("Move to Trash", kVK_Delete, .command),
                sc("AirDrop", kVK_ANSI_R, [.shift, .command]),
            ]),
            bindings: [
                click(MouseButtons.back): ActionConfig(.back),
                click(MouseButtons.forward): ActionConfig(.forward),
                TriggerKey(button: MouseButtons.middle, kind: .click): sc("Quick Look", kVK_Space),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"],
            ring: RingConfig([
                debug.start,
                sc("AI Chat", kVK_ANSI_L, .command),
                debug.stop,
                debug.restart,
                sc("Command Palette", kVK_ANSI_P, [.shift, .command]),
                sc("Terminal", kVK_ANSI_Grave, .control),
                sc("Inline Edit", kVK_ANSI_K, .command),
                sc("Agent", kVK_ANSI_I, .command),
            ]),
            bindings: codeEditorBindings,
            extras: [debug.runWithoutDebugging, debug.breakpoint] + codeEditorExtras
        ),
        AppPreset(
            name: "Visual Studio Code",
            bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.exafunction.windsurf", "com.vscodium"],
            ring: RingConfig([
                debug.start,
                debug.runWithoutDebugging,
                debug.stop,
                debug.restart,
                sc("Command Palette", kVK_ANSI_P, [.shift, .command]),
                sc("Terminal", kVK_ANSI_Grave, .control),
                debug.breakpoint,
                sc("Quick Open", kVK_ANSI_P, .command),
            ]),
            bindings: codeEditorBindings,
            extras: codeEditorExtras
        ),
        AppPreset(
            name: "Xcode", bundleIDs: ["com.apple.dt.Xcode"],
            ring: RingConfig([
                sc("Build", kVK_ANSI_B, .command),
                sc("Run", kVK_ANSI_R, .command),
                sc("Stop", kVK_ANSI_Period, .command),
                sc("Clean Build Folder", kVK_ANSI_K, [.shift, .command]),
                sc("Open Quickly", kVK_ANSI_O, [.shift, .command]),
                sc("Toggle Navigator", kVK_ANSI_0, .command),
                sc("Toggle Debug Area", kVK_ANSI_Y, [.shift, .command]),
                sc("Toggle Comment", kVK_ANSI_Slash, .command),
            ]),
            bindings: [
                click(MouseButtons.back): sc("Go Back", kVK_LeftArrow, [.control, .command]),
                click(MouseButtons.forward): sc("Go Forward", kVK_RightArrow, [.control, .command]),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ],
            extras: [
                sc("Test", kVK_ANSI_U, .command),
                sc("Toggle Breakpoint", kVK_ANSI_Backslash, .command),
                sc("Step Over", kVK_F6),
                sc("Step Into", kVK_F7),
                sc("Step Out", kVK_F8),
                sc("Jump to Definition", kVK_ANSI_J, [.control, .command]),
                sc("Find in Project", kVK_ANSI_F, [.shift, .command]),
                sc("Show Library", kVK_ANSI_L, [.shift, .command]),
                sc("Toggle Canvas", kVK_Return, [.option, .command]),
                sc("Toggle Inspectors", kVK_ANSI_0, [.option, .command]),
            ]
        ),
        AppPreset(
            name: "Adobe Photoshop", bundleIDs: ["com.adobe.Photoshop"],
            ring: RingConfig([
                sc("Brush", kVK_ANSI_B),
                sc("Eraser", kVK_ANSI_E),
                sc("Move", kVK_ANSI_V),
                sc("Lasso", kVK_ANSI_L),
                sc("Hand", kVK_ANSI_H),
                sc("Zoom", kVK_ANSI_Z),
                sc("Swap Colors", kVK_ANSI_X),
                sc("New Layer", kVK_ANSI_N, [.shift, .option, .command]),
            ]),
            bindings: [
                click(MouseButtons.back): ActionConfig(.undo),
                click(MouseButtons.forward): ActionConfig(.redo),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Figma", bundleIDs: ["com.figma.Desktop"],
            ring: RingConfig([
                sc("Frame", kVK_ANSI_F),
                sc("Rectangle", kVK_ANSI_R),
                sc("Text", kVK_ANSI_T),
                sc("Pen", kVK_ANSI_P),
                sc("Comment", kVK_ANSI_C),
                sc("Component", kVK_ANSI_K, [.option, .command]),
                sc("Group", kVK_ANSI_G, .command),
                sc("Auto Layout", kVK_ANSI_A, .shift),
            ]),
            bindings: [
                click(MouseButtons.back): ActionConfig(.undo),
                click(MouseButtons.forward): ActionConfig(.redo),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Final Cut Pro", bundleIDs: ["com.apple.FinalCut", "com.apple.FinalCutTrial"],
            ring: RingConfig([
                sc("Blade", kVK_ANSI_B),
                sc("Select", kVK_ANSI_A),
                sc("Trim", kVK_ANSI_T),
                sc("Blade at Playhead", kVK_ANSI_B, .command),
                sc("Play / Pause", kVK_Space),
                sc("Mark In", kVK_ANSI_I),
                sc("Mark Out", kVK_ANSI_O),
                sc("Snapping", kVK_ANSI_N),
            ]),
            bindings: [
                click(MouseButtons.back): sc("Previous Frame", kVK_LeftArrow),
                click(MouseButtons.forward): sc("Next Frame", kVK_RightArrow),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Adobe Premiere Pro", bundleIDs: ["com.adobe.PremierePro"],
            ring: RingConfig([
                sc("Razor", kVK_ANSI_C),
                sc("Selection", kVK_ANSI_V),
                sc("Ripple Edit", kVK_ANSI_B),
                sc("Add Edit", kVK_ANSI_K, .command),
                sc("Play / Pause", kVK_Space),
                sc("Mark In", kVK_ANSI_I),
                sc("Mark Out", kVK_ANSI_O),
                sc("Ripple Delete", kVK_ForwardDelete, .shift),
            ]),
            bindings: [
                click(MouseButtons.back): sc("Previous Frame", kVK_LeftArrow),
                click(MouseButtons.forward): sc("Next Frame", kVK_RightArrow),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Zoom", bundleIDs: ["us.zoom.xos"],
            ring: RingConfig([
                sc("Mute / Unmute", kVK_ANSI_A, [.shift, .command]),
                sc("Video On / Off", kVK_ANSI_V, [.shift, .command]),
                sc("Share Screen", kVK_ANSI_S, [.shift, .command]),
                sc("Chat", kVK_ANSI_H, [.shift, .command]),
                sc("Participants", kVK_ANSI_U, .command),
                sc("Raise Hand", kVK_ANSI_Y, .option),
                sc("Gallery View", kVK_ANSI_W, [.shift, .command]),
                sc("Leave Meeting", kVK_ANSI_W, .command),
            ]),
            bindings: [
                click(MouseButtons.forward): sc("Mute / Unmute", kVK_ANSI_A, [.shift, .command]),
                click(MouseButtons.back): sc("Video On / Off", kVK_ANSI_V, [.shift, .command]),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Microsoft Teams", bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"],
            ring: RingConfig([
                sc("Mute / Unmute", kVK_ANSI_M, [.shift, .command]),
                sc("Camera On / Off", kVK_ANSI_O, [.shift, .command]),
                sc("Share Screen", kVK_ANSI_E, [.shift, .command]),
                sc("Raise Hand", kVK_ANSI_K, [.shift, .command]),
                sc("Search", kVK_ANSI_E, .command),
                sc("Activity", kVK_ANSI_1, .command),
                sc("Chat", kVK_ANSI_2, .command),
                sc("Leave Call", kVK_ANSI_H, [.shift, .command]),
            ]),
            bindings: [
                click(MouseButtons.forward): sc("Mute / Unmute", kVK_ANSI_M, [.shift, .command]),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"],
            ring: RingConfig([
                sc("Quick Switcher", kVK_ANSI_K, .command),
                sc("Threads", kVK_ANSI_T, [.shift, .command]),
                sc("Mentions", kVK_ANSI_M, [.shift, .command]),
                sc("All Unreads", kVK_ANSI_A, [.shift, .command]),
                sc("Direct Messages", kVK_ANSI_K, [.shift, .command]),
                sc("Search", kVK_ANSI_G, .command),
                sc("New Message", kVK_ANSI_N, .command),
                sc("Huddle", kVK_ANSI_H, [.shift, .option, .command]),
            ]),
            bindings: [
                click(MouseButtons.back): ActionConfig(.back),
                click(MouseButtons.forward): ActionConfig(.forward),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Microsoft Office",
            bundleIDs: ["com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook", "com.microsoft.onenote.mac"],
            ring: RingConfig([
                ActionConfig(.copy),
                ActionConfig(.paste),
                ActionConfig(.undo),
                ActionConfig(.redo),
                sc("Bold", kVK_ANSI_B, .command),
                sc("Italic", kVK_ANSI_I, .command),
                ActionConfig(.find),
                ActionConfig(.save),
            ]),
            bindings: [
                click(MouseButtons.back): ActionConfig(.undo),
                click(MouseButtons.forward): ActionConfig(.redo),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
        AppPreset(
            name: "Spotify", bundleIDs: ["com.spotify.client"],
            ring: RingConfig([
                ActionConfig(.playPause),
                ActionConfig(.nextTrack),
                sc("Volume Up", kVK_UpArrow, .command),
                sc("Like Song", kVK_ANSI_B, [.option, .shift]),
                sc("Search", kVK_ANSI_K, .command),
                sc("Volume Down", kVK_DownArrow, .command),
                ActionConfig(.previousTrack),
                sc("Shuffle", kVK_ANSI_S, .control),
            ]),
            bindings: [
                click(MouseButtons.back): ActionConfig(.previousTrack),
                click(MouseButtons.forward): ActionConfig(.nextTrack),
                TriggerKey(button: MouseButtons.middle, kind: .click): ActionConfig(.playPause),
                hold(MouseButtons.back): ActionConfig(.actionsRing),
            ]
        ),
    ]

    private static let byBundleID: [String: AppPreset] = {
        var map: [String: AppPreset] = [:]
        for preset in all {
            for id in preset.bundleIDs where map[id] == nil { map[id] = preset }
        }
        return map
    }()

    static func preset(for bundleID: String) -> AppPreset? {
        byBundleID[bundleID]
    }
}
