//
//  GesturePresets.swift
//  MouseForge
//
//  Ready-made sets of four gesture directions.
//

import Foundation

enum GesturePreset: String, CaseIterable, Identifiable {
    case windowsDesktop, media, zoom, appNavigation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowsDesktop: return "Windows & Desktop"
        case .media: return "Media Control"
        case .zoom: return "Zoom"
        case .appNavigation: return "App Navigation"
        }
    }

    var symbol: String {
        switch self {
        case .windowsDesktop: return "rectangle.3.group"
        case .media: return "playpause"
        case .zoom: return "plus.magnifyingglass"
        case .appNavigation: return "arrow.left.arrow.right"
        }
    }

    var actions: [GestureDirection: ActionConfig] {
        switch self {
        case .windowsDesktop:
            return [.up: ActionConfig(.missionControl), .down: ActionConfig(.appExpose),
                    .left: ActionConfig(.spaceLeft), .right: ActionConfig(.spaceRight)]
        case .media:
            return [.up: ActionConfig(.volumeUp), .down: ActionConfig(.volumeDown),
                    .left: ActionConfig(.previousTrack), .right: ActionConfig(.nextTrack)]
        case .zoom:
            return [.up: ActionConfig(.zoomIn), .down: ActionConfig(.zoomOut),
                    .left: ActionConfig(.zoomReset), .right: ActionConfig(.smartZoom)]
        case .appNavigation:
            return [.up: ActionConfig(.switchApp), .down: ActionConfig(.hideApp),
                    .left: ActionConfig(.back), .right: ActionConfig(.forward)]
        }
    }

    /// The preset matching a button's current gestures, if any.
    static func matching(_ actions: [GestureDirection: ActionConfig]) -> GesturePreset? {
        allCases.first { $0.actions == actions }
    }
}
