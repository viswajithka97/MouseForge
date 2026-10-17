//
//  EventLogView.swift
//  MouseForge
//
//  Live view of the mouse events the tap is seeing. The view model pulls
//  from InputEventLog ten times a second instead of the tap pushing to the
//  UI, so the tap thread never waits on the main thread.
//

import Combine
import SwiftUI

@MainActor
final class EventLogModel: ObservableObject {
    @Published private(set) var records: [InputEventRecord] = []
    @Published private(set) var totalCount: UInt64 = 0

    private let log: InputEventLog
    private let maxVisible = 200
    private var timer: Timer?

    init(log: InputEventLog) {
        self.log = log
    }

    func startPolling() {
        guard timer == nil else { return }
        log.isCapturing = true
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        log.isCapturing = false
    }

    func clear() {
        records.removeAll()
    }

    private func poll() {
        let (newRecords, total) = log.drain()
        if total != totalCount { totalCount = total }
        guard !newRecords.isEmpty else { return }
        // Newest first.
        records.insert(contentsOf: newRecords.reversed(), at: 0)
        if records.count > maxVisible {
            records.removeLast(records.count - maxVisible)
        }
    }
}

struct EventLogView: View {
    @ObservedObject var state: AppState
    @StateObject var model: EventLogModel

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                statusBadge
                Spacer()
                Text("\(model.totalCount) events seen")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Clear") { model.clear() }
            }
            .padding(12)

            Divider()

            if model.records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "computermouse")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Click any mouse button or scroll to see events here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.records) { record in
                    HStack(spacing: 12) {
                        Text(Self.timeFormatter.string(from: record.time))
                            .foregroundStyle(.secondary)
                        Text(record.modifierSummary)
                            .frame(width: 44, alignment: .leading)
                        Text(record.summary)
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
        .frame(minWidth: 620, minHeight: 380)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state.tapStatus {
        case .running where state.isEnabled:
            Label("Event tap active, remapping on", systemImage: "circle.fill").foregroundStyle(.green)
        case .running:
            Label("Event tap active, remapping paused", systemImage: "pause.circle.fill").foregroundStyle(.secondary)
        case .waitingForPermission:
            Label("Waiting for Accessibility permission", systemImage: "lock.fill").foregroundStyle(.orange)
        case .failed:
            Label("Event tap failed to start", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
