//
//  AppWatcher.swift
//  MouseForge
//
//  Publishes the frontmost app's bundle ID. NSWorkspace tells us the
//  moment the user switches apps, so profiles change instantly.
//

import AppKit
import Combine

@MainActor
final class AppWatcher: ObservableObject {
    @Published private(set) var frontmostBundleID: String?
    @Published private(set) var frontmostName: String?

    private var observer: NSObjectProtocol?

    init() {
        update(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.update(app) }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func update(_ app: NSRunningApplication?) {
        frontmostBundleID = app?.bundleIdentifier
        frontmostName = app?.localizedName
    }
}
