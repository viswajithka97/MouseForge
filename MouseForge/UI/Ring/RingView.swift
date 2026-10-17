//
//  RingView.swift
//  MouseForge
//
//  The radial overlay: 8 slot bubbles around a center cancel zone, with
//  the hovered slot enlarged and its sector highlighted.
//

import AppKit
import SwiftUI

struct RingView: View {
    @ObservedObject var model: RingViewModel

    var body: some View {
        let diameter = model.size.diameter
        let bubble = diameter * 0.2
        let radius = diameter / 2 - bubble * 0.72
        let center = CGPoint(x: diameter / 2, y: diameter / 2)

        ZStack {
            VisualEffectBackground()
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 6)

            if let hovered = model.hovered {
                SectorShape(index: hovered, count: RingConfig.slotCount, innerRatio: 0.3)
                    .fill(Color.accentColor.opacity(model.slots[hovered] == nil ? 0.08 : 0.22))
                    .animation(.easeOut(duration: 0.12), value: hovered)
            }

            ForEach(0..<RingConfig.slotCount, id: \.self) { index in
                SlotBubble(action: model.slots[index], isHovered: model.hovered == index, size: bubble)
                    .position(RingGeometry.position(ofSlot: index, center: center, radius: radius))
            }

            centerLabel(diameter: diameter)
                .position(center)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(model.isOpen ? 1 : 0.6)
        .opacity(model.isOpen ? 1 : 0)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: model.isOpen)
        .animation(.easeOut(duration: 0.12), value: model.hovered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centerLabel(diameter: CGFloat) -> some View {
        let size = diameter * 0.3
        let action = model.hovered.flatMap { model.slots[$0] }
        return ZStack {
            Circle()
                .fill(model.hovered == nil ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05))
            VStack(spacing: 2) {
                if let action {
                    Text(ActionLibrary.displayName(for: action))
                        .font(.system(size: diameter * 0.036, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: diameter * 0.05, weight: .semibold))
                    Text(model.hovered == nil ? "Cancel" : "Empty")
                        .font(.system(size: diameter * 0.032))
                    if model.hovered == nil {
                        Text(model.subtitle)
                            .font(.system(size: diameter * 0.026))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: size, height: size)
    }
}

private struct SlotBubble: View {
    let action: ActionConfig?
    let isHovered: Bool
    let size: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(isHovered && action != nil ? Color.accentColor : Color.primary.opacity(0.09))
                Image(systemName: action.map(ActionLibrary.symbol(for:)) ?? "plus")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(isHovered && action != nil ? Color.white : (action == nil ? Color.secondary : Color.primary))
            }
            .frame(width: size * 0.7, height: size * 0.7)
            Text(action.map(ActionLibrary.displayName(for:)) ?? "")
                .font(.system(size: size * 0.15, weight: isHovered ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: size * 1.15)
        }
        .scaleEffect(isHovered ? 1.14 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// A ring-shaped wedge for one slot.
struct SectorShape: Shape {
    let index: Int
    let count: Int
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let sector = 360.0 / Double(count)
        // SwiftUI angles: 0° = east, clockwise in flipped view coordinates.
        let mid = -90 + sector * Double(index)
        let start = Angle(degrees: mid - sector / 2)
        let end = Angle(degrees: mid + sector / 2)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Always-active blur, so the ring looks right even though its window
/// never becomes key.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
