//
//  MouseIllustration.swift
//  MouseForge
//
//  An original vector drawing of a mouse (seen from above) with clickable
//  button hotspots. Two styles: a standard symmetric mouse and a sculpted
//  ergonomic mouse with a thumb rest. All shapes are defined in a 240×320
//  design space and scaled to fit.
//

import SwiftUI

/// How a button should be drawn.
enum ButtonMarker: Equatable {
    case none
    /// Remapped (in this profile or inherited).
    case remapped
    /// Set by this app profile, overriding All Applications.
    case overridden
    /// Left/right click while the safety lock is on.
    case locked
}

struct MouseGeometry {
    struct Part: Identifiable {
        enum Kind: Equatable {
            case button(MouseButtonNumber)
            /// A Logitech control the connected mouse doesn't have.
            case unavailable(String)
            /// Opens the thumb-wheel settings.
            case thumbWheel
        }

        let id: String
        let kind: Kind
        let path: Path
        let anchor: CGPoint
    }

    static let designSize = CGSize(width: 240, height: 320)

    let body: Path
    let details: Path
    /// Bottom-most first.
    let parts: [Part]

    func part(at point: CGPoint) -> Part? {
        parts.reversed().first { $0.path.contains(point) }
    }

    /// `gestureButton`: the virtual button number of a connected Logitech
    /// gesture button, if there is one.
    init(style: MouseStyle, in rect: CGRect, gestureButton: MouseButtonNumber? = nil) {
        let scale = min(rect.width / Self.designSize.width, rect.height / Self.designSize.height)
        let origin = CGPoint(
            x: rect.midX - Self.designSize.width * scale / 2,
            y: rect.midY - Self.designSize.height * scale / 2
        )
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        let r = { (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) in
            CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: w * scale, height: h * scale)
        }
        let pill = { (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) in
            Path(roundedRect: r(x, y, w, h), cornerRadius: min(w, h) * scale / 2, style: .continuous)
        }

        switch style {
        case .generic:
            self = Self.generic(p: p, pill: pill)
        case .ergonomic:
            self = Self.ergonomic(p: p, r: r, pill: pill, gestureButton: gestureButton)
        }
    }

    private init(body: Path, details: Path, parts: [Part]) {
        self.body = body
        self.details = details
        self.parts = parts
    }

    private static func center(_ path: Path) -> CGPoint {
        CGPoint(x: path.boundingRect.midX, y: path.boundingRect.midY)
    }

    // MARK: Standard mouse

    private static func generic(
        p: (CGFloat, CGFloat) -> CGPoint,
        pill: (CGFloat, CGFloat, CGFloat, CGFloat) -> Path
    ) -> MouseGeometry {
        let body = Path { path in
            path.move(to: p(120, 10))
            path.addCurve(to: p(210, 140), control1: p(172, 10), control2: p(210, 58))
            path.addCurve(to: p(120, 310), control1: p(210, 250), control2: p(172, 310))
            path.addCurve(to: p(30, 140), control1: p(68, 310), control2: p(30, 250))
            path.addCurve(to: p(120, 10), control1: p(30, 58), control2: p(68, 10))
            path.closeSubpath()
        }
        let left = Path { path in
            path.move(to: p(120, 10))
            path.addCurve(to: p(30, 140), control1: p(68, 10), control2: p(30, 58))
            path.addLine(to: p(120, 140))
            path.closeSubpath()
        }
        let right = Path { path in
            path.move(to: p(120, 10))
            path.addCurve(to: p(210, 140), control1: p(172, 10), control2: p(210, 58))
            path.addLine(to: p(120, 140))
            path.closeSubpath()
        }
        let wheel = pill(111, 46, 18, 50)
        let forward = pill(20, 158, 18, 40)
        let back = pill(22, 204, 18, 40)
        let details = Path { path in
            // Wheel ridges.
            for y in stride(from: CGFloat(56), through: 86, by: 7) {
                path.move(to: p(114, y))
                path.addLine(to: p(126, y))
            }
        }

        return MouseGeometry(body: body, details: details, parts: [
            Part(id: "left", kind: .button(MouseButtons.left), path: left, anchor: p(78, 92)),
            Part(id: "right", kind: .button(MouseButtons.right), path: right, anchor: p(162, 92)),
            Part(id: "forward", kind: .button(MouseButtons.forward), path: forward, anchor: center(forward)),
            Part(id: "back", kind: .button(MouseButtons.back), path: back, anchor: center(back)),
            Part(id: "wheel", kind: .button(MouseButtons.middle), path: wheel, anchor: center(wheel)),
        ])
    }

    // MARK: Ergonomic mouse

    private static func ergonomic(
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect,
        pill: (CGFloat, CGFloat, CGFloat, CGFloat) -> Path,
        gestureButton: MouseButtonNumber?
    ) -> MouseGeometry {
        // Right-handed: tall right flank, a waist on the left, and a thumb
        // rest flaring out at the lower left.
        let body = Path { path in
            path.move(to: p(132, 8))
            path.addCurve(to: p(222, 130), control1: p(188, 8), control2: p(222, 56))
            path.addCurve(to: p(142, 312), control1: p(222, 232), control2: p(196, 312))
            path.addCurve(to: p(18, 284), control1: p(100, 312), control2: p(48, 306))
            path.addCurve(to: p(34, 222), control1: p(-4, 266), control2: p(4, 230))
            path.addCurve(to: p(46, 134), control1: p(52, 216), control2: p(46, 178))
            path.addCurve(to: p(132, 8), control1: p(44, 60), control2: p(74, 8))
            path.closeSubpath()
        }
        let left = Path { path in
            path.move(to: p(132, 8))
            path.addCurve(to: p(46, 134), control1: p(74, 8), control2: p(44, 60))
            path.addLine(to: p(129, 128))
            path.closeSubpath()
        }
        let right = Path { path in
            path.move(to: p(132, 8))
            path.addCurve(to: p(222, 130), control1: p(188, 8), control2: p(222, 56))
            path.addLine(to: p(129, 128))
            path.closeSubpath()
        }
        let wheel = pill(122, 36, 18, 52)
        let thumbWheel = pill(30, 140, 14, 30)
        let forward = pill(30, 175, 22, 15)
        let back = pill(30, 194, 22, 15)
        let gesture = Path(ellipseIn: r(14, 240, 52, 34))
        let details = Path { path in
            for y in stride(from: CGFloat(46), through: 78, by: 7) {
                path.move(to: p(125, y))
                path.addLine(to: p(137, y))
            }
            for y in stride(from: CGFloat(146), through: 164, by: 5) {
                path.move(to: p(33, y))
                path.addLine(to: p(41, y))
            }
            // Small mode button behind the wheel (decorative).
            path.addEllipse(in: r(126, 98, 10, 10))
        }

        return MouseGeometry(body: body, details: details, parts: [
            Part(id: "gesture", kind: gestureButton.map { .button($0) } ?? .unavailable("Gesture Button"), path: gesture, anchor: center(gesture)),
            Part(id: "left", kind: .button(MouseButtons.left), path: left, anchor: p(92, 86)),
            Part(id: "right", kind: .button(MouseButtons.right), path: right, anchor: p(176, 86)),
            Part(id: "thumbWheel", kind: .thumbWheel, path: thumbWheel, anchor: center(thumbWheel)),
            Part(id: "forward", kind: .button(MouseButtons.forward), path: forward, anchor: center(forward)),
            Part(id: "back", kind: .button(MouseButtons.back), path: back, anchor: center(back)),
            Part(id: "wheel", kind: .button(MouseButtons.middle), path: wheel, anchor: center(wheel)),
        ])
    }
}

struct MouseIllustration: View {
    let style: MouseStyle
    var gestureButton: MouseButtonNumber? = nil
    let selected: MouseButtonNumber?
    let marker: (MouseButtonNumber) -> ButtonMarker
    let describe: (MouseButtonNumber) -> String
    let onSelect: (MouseButtonNumber) -> Void
    var onThumbWheel: () -> Void = {}

    @State private var hoveredPartID: String?

    var body: some View {
        GeometryReader { proxy in
            let geometry = MouseGeometry(
                style: style,
                in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 12, dy: 12),
                gestureButton: gestureButton
            )
            ZStack {
                geometry.body
                    .fill(LinearGradient(
                        colors: [Color.primary.opacity(0.07), Color.primary.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                geometry.body
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1.5)

                ForEach(geometry.parts) { part in
                    partView(part)
                }

                geometry.details
                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                    .allowsHitTesting(false)

                ForEach(geometry.parts) { part in
                    if case .button(let button) = part.kind {
                        markerView(marker(button))
                            .position(part.anchor)
                            .allowsHitTesting(false)
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let id = geometry.part(at: point)?.id
                    if id != hoveredPartID { hoveredPartID = id }
                case .ended:
                    hoveredPartID = nil
                }
            }
            .onTapGesture { point in
                switch geometry.part(at: point)?.kind {
                case .button(let button): onSelect(button)
                case .thumbWheel: onThumbWheel()
                default: break
                }
            }
            .overlay(alignment: .bottom) {
                caption(for: geometry.parts.first { $0.id == hoveredPartID })
                    .offset(y: 8)
            }
            .animation(.easeOut(duration: 0.12), value: hoveredPartID)
            .animation(.easeOut(duration: 0.15), value: selected)
        }
        .accessibilityHidden(true) // The button chips below are the accessible equivalent.
    }

    @ViewBuilder
    private func partView(_ part: MouseGeometry.Part) -> some View {
        let hovered = hoveredPartID == part.id
        switch part.kind {
        case .button(let button):
            let isSelected = selected == button
            part.path.fill(
                isSelected ? Color.accentColor.opacity(0.4)
                    : hovered ? Color.accentColor.opacity(0.2)
                    : Color.primary.opacity(0.04)
            )
            part.path.stroke(
                isSelected || hovered ? Color.accentColor : Color.primary.opacity(0.35),
                lineWidth: isSelected ? 2 : 1.2
            )
        case .unavailable:
            part.path.fill(Color.primary.opacity(hovered ? 0.08 : 0.03))
            part.path.stroke(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        case .thumbWheel:
            part.path.fill(hovered ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.04))
            part.path.stroke(hovered ? Color.accentColor : Color.primary.opacity(0.35), lineWidth: 1.2)
        }
    }

    @ViewBuilder
    private func markerView(_ marker: ButtonMarker) -> some View {
        switch marker {
        case .none:
            EmptyView()
        case .remapped:
            Circle().fill(Color.accentColor).frame(width: 9, height: 9)
                .overlay(Circle().stroke(.background, lineWidth: 1.5))
        case .overridden:
            Circle().fill(Color.orange).frame(width: 9, height: 9)
                .overlay(Circle().stroke(.background, lineWidth: 1.5))
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func caption(for part: MouseGeometry.Part?) -> some View {
        if let part {
            Group {
                switch part.kind {
                case .button(let button):
                    Text("\(MouseButtons.name(button)): \(describe(button))")
                case .unavailable(let name):
                    Text("\(name): connect a Logitech mouse that has one")
                case .thumbWheel:
                    Text("Thumb wheel: click to set it up")
                }
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .transition(.opacity)
        }
    }
}
