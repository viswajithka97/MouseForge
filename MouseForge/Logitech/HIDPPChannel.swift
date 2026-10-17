//
//  HIDPPChannel.swift
//  MouseForge
//
//  Request/response over one HID++ interface (a receiver or a directly
//  connected device). Requests are serialized (devices handle one at a
//  time), matched to replies by device index, feature index, function and
//  software id, and time out if the device doesn't answer (e.g. asleep).
//  Everything else that arrives is a notification.
//

import Foundation
import os

/// Where HID++ reports go out and come in. The real one wraps an
/// IOHIDDevice; tests use a simulated device.
protocol HIDPPTransport: AnyObject {
    func send(_ report: [UInt8]) throws
    /// Set by the channel; the transport calls it for every input report.
    var onReport: (([UInt8]) -> Void)? { get set }
}

final class HIDPPChannel: @unchecked Sendable {
    let transport: HIDPPTransport
    /// Called (on the transport's thread) for messages that aren't replies.
    var onNotification: ((HIDPP.Message) -> Void)?

    private struct Pending {
        let id: UInt64
        let deviceIndex: UInt8
        let featureIndex: UInt8
        let functionByte: UInt8
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    private let lock = NSLock()
    private var pending: Pending?
    private var nextID: UInt64 = 0
    private var softwareID: UInt8 = 0
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let logger = Logger(subsystem: "com.mouse.forge.MouseForge", category: "HIDPP")

    init(transport: HIDPPTransport) {
        self.transport = transport
        transport.onReport = { [weak self] bytes in self?.receive(bytes) }
    }

    /// Sends a request and returns the reply's 16 parameter bytes.
    func request(
        device: UInt8, featureIndex: UInt8, function: UInt8, params: [UInt8] = [],
        timeout: TimeInterval = 2
    ) async throws -> [UInt8] {
        await acquire()
        defer { release() }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            nextID &+= 1
            softwareID = softwareID % 15 + 1 // 1…15; 0 is for notifications
            let id = nextID
            let message = HIDPP.Message(deviceIndex: device, featureIndex: featureIndex, function: function, softwareID: softwareID, params: params)
            pending = Pending(id: id, deviceIndex: device, featureIndex: featureIndex, functionByte: message.bytes[3], continuation: continuation)
            lock.unlock()

            do {
                try transport.send(message.bytes)
            } catch {
                finish(id: id, with: .failure(error))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(id: id, with: .failure(HIDPP.Failure.timeout))
            }
        }
    }

    /// Fails any request in flight (device went away).
    func cancelAll() {
        lock.lock()
        let current = pending
        pending = nil
        lock.unlock()
        current?.continuation.resume(throwing: HIDPP.Failure.disconnected)
    }

    // MARK: - Incoming

    private func receive(_ bytes: [UInt8]) {
        guard let message = HIDPP.Message(bytes: bytes) else { return }
        lock.lock()
        let current = pending
        lock.unlock()

        if let current, message.deviceIndex == current.deviceIndex {
            if let error = message.errorInfo, error.featureIndex == current.featureIndex, error.functionByte == current.functionByte {
                finish(id: current.id, with: .failure(HIDPP.Failure.deviceError(error.code)))
                return
            }
            if !message.isError, message.featureIndex == current.featureIndex,
               message.bytes[3] == current.functionByte {
                finish(id: current.id, with: .success(message.params))
                return
            }
        }
        // A reply nobody is waiting for (e.g. one that arrived after its
        // timeout) is not an event. Device events use software id 0;
        // receiver notifications (sub IDs 0x40+) use that byte otherwise.
        if message.isError || (message.softwareID != 0 && message.featureIndex < 0x40) { return }
        onNotification?(message)
    }

    private func finish(id: UInt64, with result: Result<[UInt8], Error>) {
        lock.lock()
        guard let current = pending, current.id == id else {
            lock.unlock()
            return
        }
        pending = nil
        lock.unlock()
        current.continuation.resume(with: result)
    }

    // MARK: - One request at a time

    private func acquire() async {
        let acquired: Bool = lock.withLock {
            guard !busy else { return false }
            busy = true
            return true
        }
        if acquired { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let acquiredNow: Bool = lock.withLock {
                guard !busy else {
                    waiters.append(continuation)
                    return false
                }
                busy = true
                return true
            }
            if acquiredNow { continuation.resume() }
        }
    }

    private func release() {
        lock.lock()
        if waiters.isEmpty {
            busy = false
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }
}
