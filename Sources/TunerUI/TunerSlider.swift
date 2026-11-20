import SwiftUI

/// A slim slider with a filled track, drawn here so it looks the same in every row and tint.
struct TunerSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false
    @State private var isHovering = false

    private static let trackHeight: CGFloat = 6
    private static let thumbSize: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - Self.thumbSize, 1)
            let position = Self.thumbSize / 2 + travel * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: position, height: Self.trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: isDragging ? 4 : 2, y: 1)
                    .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .scaleEffect(isDragging ? 1.15 : (isHovering ? 1.07 : 1))
                    .offset(x: position - Self.thumbSize / 2)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        setFraction((drag.location.x - Self.thumbSize / 2) / travel)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isDragging)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .frame(height: Self.thumbSize + 4)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(value))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span) : 0
    }

    private func setFraction(_ fraction: CGFloat) {
        let raw = range.lowerBound + Double(min(max(fraction, 0), 1)) * (range.upperBound - range.lowerBound)
        let stepped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        value = min(max(stepped, range.lowerBound), range.upperBound)
    }
}
