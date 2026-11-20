/// The base settings of a PXN V10 Pro wheel base: its steering range and how it plays force feedback.
///
/// The base keeps these itself. They travel in one packet on its vendor USB interface (HID report 1), with
/// the same layout whether the base is reporting them or being told them. Bytes the packet carries that
/// PXN's own software neither names nor writes are left out here; the base ignores what is sent for them.
public struct BaseSettings: Equatable, Sendable {
    /// Lock to lock, in degrees.
    public var steeringRange: Int
    /// Overall strength of a game's force feedback, in percent.
    public var gameForceFeedback: Int
    /// Strength of a game's spring effects, in percent.
    public var spring: Int
    /// Strength of a game's damper effects, in percent.
    public var damper: Int
    /// Strength of a game's sine (vibration) effects, in percent.
    public var sineWave: Int
    /// Ceiling on the motor's torque, in percent.
    public var maxTorque: Int
    /// The base's own centring spring, in percent. It acts whether or not a game is running.
    public var mechanicalCentering: Int
    /// The base's own damping, in percent. It acts whether or not a game is running.
    public var mechanicalDamping: Int
    /// How much fine road detail the base lets through, in percent.
    public var roadDetail: Int
    /// Reverses the direction of every force.
    public var invertForceFeedback: Bool
    /// Strength level of the stop at each end of the steering range. Shown as the base reports it; the
    /// levels PXN's software offers are not known, so the app does not change it.
    public var endStopStrength: Int
    /// Strength of a game's friction effects, in percent.
    public var gameFriction: Int

    public init(
        steeringRange: Int, gameForceFeedback: Int, spring: Int, damper: Int, sineWave: Int, maxTorque: Int,
        mechanicalCentering: Int, mechanicalDamping: Int, roadDetail: Int, invertForceFeedback: Bool,
        endStopStrength: Int, gameFriction: Int
    ) {
        self.steeringRange = steeringRange
        self.gameForceFeedback = gameForceFeedback
        self.spring = spring
        self.damper = damper
        self.sineWave = sineWave
        self.maxTorque = maxTorque
        self.mechanicalCentering = mechanicalCentering
        self.mechanicalDamping = mechanicalDamping
        self.roadDetail = roadDetail
        self.invertForceFeedback = invertForceFeedback
        self.endStopStrength = endStopStrength
        self.gameFriction = gameFriction
    }
}

// MARK: - The packet

extension BaseSettings {
    /// The HID report the settings travel in, on the base's vendor interface.
    public static let reportID: UInt8 = 0x01
    /// Reports on that interface are this long, report id included; shorter packets are zero padded.
    public static let reportLength = 63
    /// Asks the base for its settings. It answers with the same four bytes followed by the settings.
    public static let queryPacket: [UInt8] = [0x01, 0x81, 0xE0, 0x22]

    static let writeHeader: [UInt8] = [0x01, 0x41, 0xE0, 0x22]
    static let packetLength = 35
    /// PXN's software always writes this for the base's inertia, which it does not let the user change.
    static let inertia: UInt8 = 100

    enum Offset {
        static let steeringRangeLow = 4
        static let steeringRangeHigh = 5
        static let gameForceFeedback = 6
        static let spring = 7
        static let damper = 8
        static let sineWave = 9
        static let inertia = 10
        static let maxTorque = 11
        static let mechanicalCentering = 13
        static let mechanicalDamping = 14
        static let roadDetail = 15
        static let invertForceFeedback = 17
        static let endStopStrength = 18
        static let gameFriction = 34
    }

    /// Reads the base's answer to `queryPacket`. Nil for any other report.
    public init?(reply: [UInt8]) {
        guard reply.count >= Self.packetLength, Array(reply[0..<4]) == Self.queryPacket else { return nil }
        self.init(
            steeringRange: Int(reply[Offset.steeringRangeLow]) | Int(reply[Offset.steeringRangeHigh]) << 8,
            gameForceFeedback: Int(reply[Offset.gameForceFeedback]),
            spring: Int(reply[Offset.spring]),
            damper: Int(reply[Offset.damper]),
            sineWave: Int(reply[Offset.sineWave]),
            maxTorque: Int(reply[Offset.maxTorque]),
            mechanicalCentering: Int(reply[Offset.mechanicalCentering]),
            mechanicalDamping: Int(reply[Offset.mechanicalDamping]),
            roadDetail: Int(reply[Offset.roadDetail]),
            invertForceFeedback: reply[Offset.invertForceFeedback] != 0,
            endStopStrength: Int(reply[Offset.endStopStrength]),
            gameFriction: Int(reply[Offset.gameFriction])
        )
    }

    /// The packet that sets the base to these settings, each value brought into the range the base takes.
    public func writePacket() -> [UInt8] {
        let settings = clamped()
        var packet = [UInt8](repeating: 0, count: Self.packetLength)
        packet.replaceSubrange(0..<4, with: Self.writeHeader)
        packet[Offset.steeringRangeLow] = UInt8(settings.steeringRange & 0xFF)
        packet[Offset.steeringRangeHigh] = UInt8(settings.steeringRange >> 8)
        packet[Offset.gameForceFeedback] = UInt8(settings.gameForceFeedback)
        packet[Offset.spring] = UInt8(settings.spring)
        packet[Offset.damper] = UInt8(settings.damper)
        packet[Offset.sineWave] = UInt8(settings.sineWave)
        packet[Offset.inertia] = Self.inertia
        packet[Offset.maxTorque] = UInt8(settings.maxTorque)
        packet[Offset.mechanicalCentering] = UInt8(settings.mechanicalCentering)
        packet[Offset.mechanicalDamping] = UInt8(settings.mechanicalDamping)
        packet[Offset.roadDetail] = UInt8(settings.roadDetail)
        packet[Offset.invertForceFeedback] = settings.invertForceFeedback ? 1 : 0
        packet[Offset.endStopStrength] = UInt8(settings.endStopStrength)
        packet[Offset.gameFriction] = UInt8(settings.gameFriction)
        return packet
    }
}

// MARK: - Ranges

extension BaseSettings {
    /// A setting the user can change, with the range PXN's own software allows for it.
    public struct Field: Identifiable {
        /// Short name for the command line.
        public let key: String
        public let name: String
        public let keyPath: WritableKeyPath<BaseSettings, Int>
        public let range: ClosedRange<Int>
        public let step: Int
        public let unit: String
        public let help: String
        public var id: String { key }
    }

    public static let steeringRangeField = Field(
        key: "range", name: "Steering range", keyPath: \.steeringRange, range: 90...1800, step: 10, unit: "°",
        help: "How far the wheel turns from lock to lock.")

    public static let forceFields: [Field] = [
        Field(key: "force", name: "Force feedback", keyPath: \.gameForceFeedback, range: 0...100, step: 1, unit: "%",
              help: "Overall strength of the forces a game sends."),
        Field(key: "torque", name: "Maximum torque", keyPath: \.maxTorque, range: 30...100, step: 1, unit: "%",
              help: "Ceiling on what the motor can deliver."),
    ]

    public static let effectFields: [Field] = [
        Field(key: "spring", name: "Spring", keyPath: \.spring, range: 0...100, step: 1, unit: "%",
              help: "Strength of a game's spring effects."),
        Field(key: "damper", name: "Damper", keyPath: \.damper, range: 0...100, step: 1, unit: "%",
              help: "Strength of a game's damper effects."),
        Field(key: "friction", name: "Friction", keyPath: \.gameFriction, range: 0...100, step: 1, unit: "%",
              help: "Strength of a game's friction effects."),
        Field(key: "vibration", name: "Vibration", keyPath: \.sineWave, range: 0...100, step: 1, unit: "%",
              help: "Strength of a game's sine wave effects."),
        Field(key: "road", name: "Road detail", keyPath: \.roadDetail, range: 0...100, step: 1, unit: "%",
              help: "How much fine road detail comes through."),
    ]

    public static let mechanicalFields: [Field] = [
        Field(key: "centring", name: "Centring spring", keyPath: \.mechanicalCentering, range: 0...100, step: 1, unit: "%",
              help: "The base's own pull toward centre, with or without a game."),
        Field(key: "damping", name: "Damping", keyPath: \.mechanicalDamping, range: 0...100, step: 1, unit: "%",
              help: "The base's own resistance to fast movement, with or without a game."),
    ]

    public static let allFields = [steeringRangeField] + forceFields + effectFields + mechanicalFields

    /// These settings with every value inside its field's range and on its step.
    public func clamped() -> BaseSettings {
        var settings = self
        for field in Self.allFields {
            let value = min(max(settings[keyPath: field.keyPath], field.range.lowerBound), field.range.upperBound)
            let steps = Int((Double(value - field.range.lowerBound) / Double(field.step)).rounded())
            settings[keyPath: field.keyPath] = field.range.lowerBound + steps * field.step
        }
        settings.endStopStrength = min(max(settings.endStopStrength, 0), 255)
        return settings
    }
}
