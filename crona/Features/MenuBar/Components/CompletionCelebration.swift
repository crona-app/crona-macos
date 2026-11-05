import SwiftUI

/// The optional flourish played on the active screen when a focus block completes.
enum CompletionCelebrationStyle: String, Codable, Equatable, CaseIterable, Identifiable {
    case off
    case glow
    case confetti

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "None"
        case .glow: return "Glow"
        case .confetti: return "Confetti"
        }
    }

    /// How long the overlay window stays up.
    var duration: TimeInterval {
        switch self {
        case .off: return 0
        case .glow: return 2.0
        case .confetti: return 3.2
        }
    }

    /// Reduce Motion keeps only the popup's checkmark.
    func resolved(reduceMotion: Bool) -> Self {
        reduceMotion ? .off : self
    }
}

/// Full-screen, click-through content for the celebration window.
/// `target` is the popup's center in this view's top-left coordinates.
struct CompletionCelebrationScreenView: View {
    let style: CompletionCelebrationStyle
    let target: CGPoint

    var body: some View {
        switch style {
        case .off: Color.clear
        case .glow: ScreenEdgeGlow()
        case .confetti: ConfettiCannons(target: target)
        }
    }
}

private struct ScreenEdgeGlow: View {
    @State private var intensity: Double = 0

    var body: some View {
        let green = PopupVisualTheme.semantic(.success)
        GeometryReader { geometry in
            let edge = min(geometry.size.width, geometry.size.height) * 0.08
            Rectangle()
                .strokeBorder(green, lineWidth: edge)
                .blur(radius: edge * 0.9)
                .opacity(0.75 * intensity)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { intensity = 1 }
            withAnimation(.easeIn(duration: 1.2).delay(0.7)) { intensity = 0 }
        }
    }
}

private struct ConfettiCannons: View {
    private static let gravity: Double = 900
    private static let lifetime: Double = 3.0
    private static let colors: [Color] = [
        Color(red: 0.30, green: 0.85, blue: 0.45), Color(red: 1.0, green: 0.80, blue: 0.20),
        Color(red: 0.35, green: 0.60, blue: 1.0), Color(red: 1.0, green: 0.42, blue: 0.55),
        Color(red: 0.70, green: 0.45, blue: 1.0), Color(red: 1.0, green: 0.60, blue: 0.25),
    ]

    let target: CGPoint
    // Random factors only; positions are worked out from the canvas size each frame,
    // so nothing depends on a layout pass having happened first.
    private let pieces: [ConfettiPiece] = (0..<220).map { ConfettiPiece.random(fromLeft: $0.isMultiple(of: 2)) }
    private let start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                for piece in pieces where t >= piece.delay {
                    let age = t - piece.delay
                    guard age < Self.lifetime else { continue }
                    let origin = CGPoint(x: piece.fromLeft ? 0 : size.width, y: size.height)
                    // Aim so the burst peaks around the popup.
                    let rise = max(120, (origin.y - target.y) * piece.riseFactor)
                    let vy = -sqrt(2 * Self.gravity * rise)
                    let vx = (target.x - origin.x) * piece.reachFactor / (-vy / Self.gravity)
                    let x = origin.x + vx * age
                    let y = origin.y + vy * age + 0.5 * Self.gravity * age * age
                    var copy = context
                    copy.opacity = min(1, max(0, (Self.lifetime - age) / 0.8))
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .degrees(piece.spin * age))
                    // Flutter: the piece turns edge-on and back as it falls.
                    copy.scaleBy(x: max(0.15, abs(cos(age * piece.flutter))), y: 1)
                    copy.fill(
                        Path(roundedRect: CGRect(x: -5, y: -2.5, width: 10, height: 5), cornerRadius: 1),
                        with: .color(Self.colors[piece.colorIndex]))
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct ConfettiPiece {
    let fromLeft: Bool
    let riseFactor: Double
    let reachFactor: Double
    let delay: Double
    let spin: Double
    let flutter: Double
    let colorIndex: Int

    static func random(fromLeft: Bool) -> Self {
        Self(
            fromLeft: fromLeft,
            riseFactor: Double.random(in: 0.85...1.2),
            reachFactor: Double.random(in: 0.45...1.05),
            delay: Double.random(in: 0...0.25),
            spin: Double.random(in: -360...360),
            flutter: Double.random(in: 4...10),
            colorIndex: Int.random(in: 0..<6))
    }
}
