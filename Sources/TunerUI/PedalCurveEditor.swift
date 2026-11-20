import SwiftUI
import WheelProtocol

/// One pedal: its response curve to drag into shape, what the pedal is putting out right now, ready-made
/// shapes, and whether it is reversed.
struct PedalCard: View {
    let pedal: PedalSettings.Pedal
    @Binding var curve: PedalCurve
    @Binding var isReversed: Bool
    /// The pedal's output right now, 0 to 1, or nil when it is not known.
    let liveOutput: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconTile(symbol: style.symbol, color: style.color)
                Text(pedal.title)
                    .font(.headline)
            }

            CurvePlot(curve: $curve, liveOutput: liveOutput, tint: style.color)
                .aspectRatio(1, contentMode: .fit)

            HStack {
                Text("Output")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(liveOutput.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
            }
            .font(.callout)

            Menu {
                ForEach(PedalCurve.Shape.allCases, id: \.self) { shape in
                    Button(shape.title) { curve = curve.reshaped(shape) }
                }
            } label: {
                Text(shapeName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .help("Ready-made curves. Drag the points to make your own.")

            Toggle("Reverse", isOn: $isReversed)
                .toggleStyle(.switch)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Swaps the pedal's released and pressed ends.")
        }
        .padding(12)
        .background(CardBackground())
    }

    /// The ready-made shape this curve matches, or that it is the user's own.
    private var shapeName: String {
        curve.shape?.title ?? "Custom"
    }

    private var style: (symbol: String, color: Color) {
        switch pedal {
        case .throttle: return ("forward.fill", .green)
        case .brake: return ("stop.fill", .red)
        case .clutch: return ("link", .blue)
        }
    }
}

/// The curve itself: travel left to right, output bottom to top. The four points drag up and down.
private struct CurvePlot: View {
    @Binding var curve: PedalCurve
    let liveOutput: Double?
    let tint: Color

    @Environment(\.isEnabled) private var isEnabled
    @State private var draggedIndex: Int?

    private static let handleSize: CGFloat = 13
    private static let space = "plot"

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.5))

                grid(in: size)
                    .stroke(.quaternary, lineWidth: 0.5)

                // Where a pedal with no curve would be.
                Path { path in
                    path.move(to: position(travel: 0, output: 0, in: size))
                    path.addLine(to: position(travel: 1, output: 1, in: size))
                }
                .stroke(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                area(in: size)
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                line(in: size)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let liveOutput {
                    liveMarker(output: liveOutput, in: size)
                }

                ForEach(curve.points.indices, id: \.self) { index in
                    let point = curve.points[index]
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(tint, lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: draggedIndex == index ? 4 : 1.5, y: 1)
                        .frame(width: Self.handleSize, height: Self.handleSize)
                        .scaleEffect(draggedIndex == index ? 1.25 : 1)
                        .position(position(travel: point.inputFraction, output: point.outputFraction, in: size))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                                .onChanged { drag in
                                    draggedIndex = index
                                    curve.setOutput(1 - Double(drag.location.y / size.height), at: index)
                                }
                                .onEnded { _ in draggedIndex = nil }
                        )
                        .accessibilityLabel("Point \(index + 1)")
                        .accessibilityValue("\(Int((point.outputFraction * 100).rounded())) percent")
                }
            }
            .coordinateSpace(name: Self.space)
            .animation(.easeOut(duration: 0.1), value: draggedIndex)
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func position(travel: Double, output: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: travel * size.width, y: (1 - output) * size.height)
    }

    /// Released, the four points, fully pressed.
    private func corners(in size: CGSize) -> [CGPoint] {
        [position(travel: 0, output: 0, in: size)]
            + curve.points.map { position(travel: $0.inputFraction, output: $0.outputFraction, in: size) }
            + [position(travel: 1, output: 1, in: size)]
    }

    private func line(in size: CGSize) -> Path {
        Path { $0.addLines(corners(in: size)) }
    }

    private func area(in size: CGSize) -> Path {
        var path = line(in: size)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    private func grid(in size: CGSize) -> Path {
        Path { path in
            for step in 1..<5 {
                let offset = CGFloat(step) / 5
                path.move(to: CGPoint(x: offset * size.width, y: 0))
                path.addLine(to: CGPoint(x: offset * size.width, y: size.height))
                path.move(to: CGPoint(x: 0, y: offset * size.height))
                path.addLine(to: CGPoint(x: size.width, y: offset * size.height))
            }
        }
    }

    /// A level line at the pedal's current output, with a dot where that output sits on the curve.
    private func liveMarker(output: Double, in size: CGSize) -> some View {
        let level = position(travel: 0, output: output, in: size).y
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: level))
                path.addLine(to: CGPoint(x: size.width, y: level))
            }
            .stroke(tint.opacity(0.55), lineWidth: 1)
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .position(position(travel: travel(forOutput: output), output: output, in: size))
        }
    }

    /// The pedal travel that gives an output: the curve read the other way round.
    private func travel(forOutput output: Double) -> Double {
        var previous = (input: 0.0, output: 0.0)
        for point in curve.points.map({ (input: $0.inputFraction, output: $0.outputFraction) }) + [(input: 1.0, output: 1.0)] {
            if output <= point.output {
                let rise = point.output - previous.output
                return rise > 0 ? previous.input + (point.input - previous.input) * (output - previous.output) / rise : previous.input
            }
            previous = point
        }
        return 1
    }
}
