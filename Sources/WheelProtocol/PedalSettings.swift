/// How a pedal's travel becomes its output: four points between the fixed ends (released gives nothing,
/// fully pressed gives everything). The base joins the six points with straight lines.
public struct PedalCurve: Equatable, Sendable {
    /// A point of the curve, as the base stores it: both axes run from 0 to 65535.
    public struct Point: Equatable, Sendable {
        public var input: UInt16
        public var output: UInt16

        public init(input: UInt16, output: UInt16) {
            self.input = input
            self.output = output
        }

        /// Pedal travel at this point, 0 released to 1 fully pressed.
        public var inputFraction: Double { Double(input) / Double(UInt16.max) }

        /// Output at this point, from 0 to 1.
        public var outputFraction: Double {
            get { Double(output) / Double(UInt16.max) }
            set { output = UInt16((min(max(newValue, 0), 1) * Double(UInt16.max)).rounded()) }
        }
    }

    public static let pointCount = 4

    /// Always `pointCount` points, in order of travel.
    public var points: [Point]

    public init(points: [Point]) {
        precondition(points.count == Self.pointCount)
        self.points = points
    }

    /// A curve through the base's usual travel positions (20, 40, 60 and 80 percent) with the output a shape
    /// gives at each.
    public init(shape: Shape) {
        self.init(points: (1...Self.pointCount).map { index in
            let travel = Double(index) / Double(Self.pointCount + 1)
            var point = Point(input: UInt16((travel * Double(UInt16.max)).rounded()), output: 0)
            point.outputFraction = shape.output(at: travel)
            return point
        })
    }

    /// Sets one point's output, held between its neighbours' so the curve never turns back on itself.
    public mutating func setOutput(_ fraction: Double, at index: Int) {
        let lower = index > 0 ? points[index - 1].outputFraction : 0
        let upper = index < points.count - 1 ? points[index + 1].outputFraction : 1
        points[index].outputFraction = min(max(fraction, lower), upper)
    }

    /// This curve with its outputs replaced by a shape's, keeping the travel positions it has.
    public func reshaped(_ shape: Shape) -> PedalCurve {
        var curve = self
        for index in curve.points.indices {
            curve.points[index].outputFraction = shape.output(at: curve.points[index].inputFraction)
        }
        return curve
    }

    /// The ready-made shape this curve is, or nil for a curve of the user's own. The base stores a shape
    /// with its own rounding, so a few counts either way still count as the shape.
    public var shape: Shape? {
        Shape.allCases.first { shape in
            zip(points, reshaped(shape).points).allSatisfy { abs(Int($0.output) - Int($1.output)) <= Self.shapeTolerance }
        }
    }

    private static let shapeTolerance = 4

    /// The output this curve gives for a pedal travel from 0 to 1.
    public func output(at travel: Double) -> Double {
        var previous = (input: 0.0, output: 0.0)
        for point in points.map({ (input: $0.inputFraction, output: $0.outputFraction) }) + [(input: 1.0, output: 1.0)] {
            if travel <= point.input {
                let span = point.input - previous.input
                return span > 0
                    ? previous.output + (point.output - previous.output) * (travel - previous.input) / span
                    : point.output
            }
            previous = point
        }
        return 1
    }

    /// Ready-made curve shapes.
    public enum Shape: String, CaseIterable, Sendable {
        /// Output follows travel.
        case linear
        /// Little happens at first, then it builds: fine control at the top of the pedal.
        case gentle
        /// A lot happens at first, then it levels off.
        case quick
        /// Gentle at both ends, steep in the middle.
        case smooth

        public var title: String {
            switch self {
            case .linear: return "Linear"
            case .gentle: return "Gentle start"
            case .quick: return "Quick start"
            case .smooth: return "S-curve"
            }
        }

        public func output(at travel: Double) -> Double {
            let x = min(max(travel, 0), 1)
            switch self {
            case .linear: return x
            case .gentle: return x * x
            case .quick: return 1 - (1 - x) * (1 - x)
            case .smooth: return x * x * (3 - 2 * x)
            }
        }
    }
}

/// The pedal settings a PXN V10 Pro wheel base keeps: a response curve for each pedal and whether each is
/// reversed. They travel on the same interface and report as the base settings, in a packet of their own.
public struct PedalSettings: Equatable, Sendable {
    public var throttle: PedalCurve
    public var brake: PedalCurve
    public var clutch: PedalCurve
    public var throttleReversed: Bool
    public var brakeReversed: Bool
    public var clutchReversed: Bool
    /// The base's dual-clutch mode and value. Carried as the base reports them and written back unchanged:
    /// what the numbers mean has not been worked out.
    public var dualClutchMode: UInt8
    public var dualClutchValue: UInt8

    public init(
        throttle: PedalCurve, brake: PedalCurve, clutch: PedalCurve,
        throttleReversed: Bool, brakeReversed: Bool, clutchReversed: Bool,
        dualClutchMode: UInt8, dualClutchValue: UInt8
    ) {
        self.throttle = throttle
        self.brake = brake
        self.clutch = clutch
        self.throttleReversed = throttleReversed
        self.brakeReversed = brakeReversed
        self.clutchReversed = clutchReversed
        self.dualClutchMode = dualClutchMode
        self.dualClutchValue = dualClutchValue
    }
}

// MARK: - The packet

extension PedalSettings {
    /// Asks the base for its pedal settings. It answers with the same four bytes followed by the settings.
    public static let queryPacket: [UInt8] = [0x01, 0x81, 0xE0, 0x23]

    static let writeHeader: [UInt8] = [0x01, 0x41, 0xE0, 0x23]
    static let packetLength = 57

    enum Offset {
        static let throttle = 4
        static let brake = 20
        static let clutch = 36
        static let dualClutchMode = 52
        static let dualClutchValue = 53
        static let throttleReversed = 54
        static let brakeReversed = 55
        static let clutchReversed = 56
    }

    /// Reads the base's answer to `queryPacket`. Nil for any other report.
    public init?(reply: [UInt8]) {
        guard reply.count >= Self.packetLength, Array(reply[0..<4]) == Self.queryPacket else { return nil }
        self.init(
            throttle: Self.curve(in: reply, at: Offset.throttle),
            brake: Self.curve(in: reply, at: Offset.brake),
            clutch: Self.curve(in: reply, at: Offset.clutch),
            throttleReversed: reply[Offset.throttleReversed] != 0,
            brakeReversed: reply[Offset.brakeReversed] != 0,
            clutchReversed: reply[Offset.clutchReversed] != 0,
            dualClutchMode: reply[Offset.dualClutchMode],
            dualClutchValue: reply[Offset.dualClutchValue])
    }

    /// The packet that sets the base to these pedal settings.
    public func writePacket() -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: Self.packetLength)
        packet.replaceSubrange(0..<4, with: Self.writeHeader)
        Self.write(throttle, into: &packet, at: Offset.throttle)
        Self.write(brake, into: &packet, at: Offset.brake)
        Self.write(clutch, into: &packet, at: Offset.clutch)
        packet[Offset.dualClutchMode] = dualClutchMode
        packet[Offset.dualClutchValue] = dualClutchValue
        packet[Offset.throttleReversed] = throttleReversed ? 1 : 0
        packet[Offset.brakeReversed] = brakeReversed ? 1 : 0
        packet[Offset.clutchReversed] = clutchReversed ? 1 : 0
        return packet
    }

    /// Each point is its travel then its output, both 16 bits, low byte first.
    private static func curve(in bytes: [UInt8], at offset: Int) -> PedalCurve {
        PedalCurve(points: (0..<PedalCurve.pointCount).map { index in
            let at = offset + index * 4
            return PedalCurve.Point(
                input: UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8,
                output: UInt16(bytes[at + 2]) | UInt16(bytes[at + 3]) << 8)
        })
    }

    private static func write(_ curve: PedalCurve, into packet: inout [UInt8], at offset: Int) {
        for (index, point) in curve.points.enumerated() {
            let at = offset + index * 4
            packet[at] = UInt8(point.input & 0xFF)
            packet[at + 1] = UInt8(point.input >> 8)
            packet[at + 2] = UInt8(point.output & 0xFF)
            packet[at + 3] = UInt8(point.output >> 8)
        }
    }
}

// MARK: - The three pedals

extension PedalSettings {
    public enum Pedal: String, CaseIterable, Identifiable, Sendable {
        case throttle, brake, clutch

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .throttle: return "Throttle"
            case .brake: return "Brake"
            case .clutch: return "Clutch"
            }
        }
    }

    public subscript(curve pedal: Pedal) -> PedalCurve {
        get {
            switch pedal {
            case .throttle: return throttle
            case .brake: return brake
            case .clutch: return clutch
            }
        }
        set {
            switch pedal {
            case .throttle: throttle = newValue
            case .brake: brake = newValue
            case .clutch: clutch = newValue
            }
        }
    }

    public subscript(reversed pedal: Pedal) -> Bool {
        get {
            switch pedal {
            case .throttle: return throttleReversed
            case .brake: return brakeReversed
            case .clutch: return clutchReversed
            }
        }
        set {
            switch pedal {
            case .throttle: throttleReversed = newValue
            case .brake: brakeReversed = newValue
            case .clutch: clutchReversed = newValue
            }
        }
    }
}
