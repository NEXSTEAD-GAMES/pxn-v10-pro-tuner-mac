import SwiftUI

/// The wheel, live: a steering wheel that turns with the real one inside a gauge of its travel.
struct WheelDial: View {
    /// -1 at full left lock, 1 at full right lock.
    let steering: Double
    /// Degrees from centre, or nil while the base's range is not known.
    let degrees: Double?
    let tint: Color

    /// The gauge spans three quarters of a circle, open at the bottom.
    private static let sweep = 0.75
    private static let lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            // A soft glow in the tint, so the dial reads as the window's centrepiece.
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(degrees == nil ? 0 : 0.22), tint.opacity(0)],
                                     center: .center, startRadius: 10, endRadius: dialRadius * 1.25))
                .scaleEffect(1.3)

            // The whole travel.
            Circle()
                .trim(from: 0, to: Self.sweep)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))

            // From centre to where the wheel is.
            Circle()
                .trim(from: min(centre, position), to: max(centre, position))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Centre mark.
            Capsule()
                .fill(.tertiary)
                .frame(width: 3, height: 9)
                .offset(y: -dialRadius - Self.lineWidth - 3)

            Image(systemName: "steeringwheel")
                .font(.system(size: 118, weight: .regular))
                .foregroundStyle(degrees == nil
                    ? AnyShapeStyle(.tertiary)
                    : AnyShapeStyle(LinearGradient(colors: [.primary.opacity(0.92), .primary.opacity(0.68)],
                                                   startPoint: .top, endPoint: .bottom)))
                .shadow(color: .black.opacity(degrees == nil ? 0 : 0.18), radius: 8, y: 4)
                .rotationEffect(.degrees(degrees ?? 0))
        }
        .frame(width: dialRadius * 2, height: dialRadius * 2)
        .padding(Self.lineWidth)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: steering)
        .accessibilityElement()
        .accessibilityLabel("Wheel position")
        .accessibilityValue(degrees.map { Text("\(Int($0.rounded())) degrees") } ?? Text("unknown"))
    }

    private let dialRadius: CGFloat = 104

    private var centre: Double { Self.sweep / 2 }

    private var position: Double {
        centre + min(max(steering, -1), 1) * Self.sweep / 2
    }
}
