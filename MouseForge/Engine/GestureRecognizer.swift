//
//  GestureRecognizer.swift
//  MouseForge
//
//  Adds up mouse movement while a gesture button is held and reports a
//  direction once it has moved far enough. The dominant axis wins, so a
//  slightly diagonal swipe still counts as up/down/left/right.
//

import CoreGraphics

struct GestureRecognizer: Equatable {
    let threshold: CGFloat
    private(set) var accumulated = CGVector.zero

    init(threshold: CGFloat) {
        self.threshold = max(threshold, 1)
    }

    /// `dx`/`dy` in screen points with y pointing down (CGEvent deltas).
    /// Returns a direction (and starts measuring afresh) when the movement
    /// passes the threshold.
    mutating func add(dx: CGFloat, dy: CGFloat) -> GestureDirection? {
        accumulated.dx += dx
        accumulated.dy += dy
        let distance = (accumulated.dx * accumulated.dx + accumulated.dy * accumulated.dy).squareRoot()
        guard distance >= threshold else { return nil }
        let direction = Self.direction(of: accumulated)
        accumulated = .zero
        return direction
    }

    static func direction(of vector: CGVector) -> GestureDirection {
        if abs(vector.dx) > abs(vector.dy) {
            return vector.dx > 0 ? .right : .left
        }
        return vector.dy > 0 ? .down : .up
    }
}
