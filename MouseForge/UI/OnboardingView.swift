//
//  OnboardingView.swift
//  MouseForge
//
//  Welcome window: explains the two permissions, lets the user grant them,
//  and updates live (PermissionsManager polls) as switches are flipped in
//  System Settings. Offers a relaunch when macOS needs one, and a few tips.
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var state: AppState
    @ObservedObject var permissions: PermissionsManager

    /// Accessibility is on but the tap still can't start, or Input
    /// Monitoring was requested this run and isn't visible yet.
    private var needsRelaunch: Bool {
        state.tapStatus == .failed
            || (permissions.inputMonitoringRequested && !permissions.inputMonitoringGranted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to MouseForge")
                        .font(.title2.bold())
                    Text(permissions.allGranted
                         ? "You're all set. Your mouse is ready to customize."
                         : "Two quick permissions and your mouse is ready.")
                        .foregroundStyle(.secondary)
                }
            }

            PermissionRow(
                step: 1,
                title: "Accessibility",
                detail: "Required. Lets MouseForge see and change clicks, scrolling, and shortcuts.",
                granted: permissions.accessibilityGranted,
                request: permissions.requestAccessibility,
                openSettings: permissions.openAccessibilitySettings,
                showApp: permissions.revealAppInFinder
            )

            PermissionRow(
                step: 2,
                title: "Input Monitoring",
                detail: "For Logitech mice: battery, DPI, SmartShift, the gesture button, thumb wheel, and haptics.",
                granted: permissions.inputMonitoringGranted,
                request: permissions.requestInputMonitoring,
                openSettings: permissions.openInputMonitoringSettings,
                showApp: permissions.revealAppInFinder
            )

            if !permissions.allGranted {
                Label {
                    Text("Already switched on in System Settings but still missing here? That entry belongs to an older build of MouseForge. In System Settings select MouseForge, remove it with “–”, then click Grant Access again.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
                .font(.callout)
            }

            if needsRelaunch {
                Label(
                    "macOS only applies some permissions after MouseForge restarts. If a switch is on in System Settings but still shows as missing here, relaunch.",
                    systemImage: "arrow.clockwise.circle.fill"
                )
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Good to know").font(.headline)
                Tip(symbol: "circle.circle", text: "Hold the Back button to open the Actions Ring.")
                Tip(symbol: "pause.circle", text: "⌃⌥⌘M turns all remapping off or on instantly.")
                Tip(symbol: "computermouse", text: "Everything else lives in the menu bar: click the mouse icon ▸ Settings.")
            }

            HStack {
                if needsRelaunch {
                    Button("Relaunch MouseForge") { PermissionsManager.relaunch() }
                }
                Spacer()
                Button(permissions.accessibilityGranted ? "Open Settings" : "Continue Later") {
                    WindowManager.shared.closeOnboarding()
                    if permissions.accessibilityGranted {
                        WindowManager.shared.showSettings()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}

private struct Tip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }
    }
}

private struct PermissionRow: View {
    let step: Int
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void
    let openSettings: () -> Void
    let showApp: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(granted ? Color.green : Color.accentColor)
                if granted {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                } else {
                    Text("\(step)").font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if granted {
                    Text("Granted").font(.caption).foregroundStyle(.green)
                } else {
                    HStack {
                        Button("Grant Access…", action: request)
                        Button("Open System Settings", action: openSettings)
                    }
                    HStack(spacing: 4) {
                        Text("Not in the list?").font(.caption).foregroundStyle(.secondary)
                        Button("Show MouseForge in Finder", action: showApp)
                            .buttonStyle(.link)
                            .font(.caption)
                        Text("and drag it into the list, or use “+”.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}
