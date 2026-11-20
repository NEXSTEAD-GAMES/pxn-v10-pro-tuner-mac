import Foundation
import WheelLink
import WheelProtocol

/// What the window shows: the base's own settings, and the edited copy waiting to be applied.
@MainActor
public final class WheelModel: ObservableObject {
    @Published public private(set) var isConnected = false
    /// The settings as the base last reported them.
    @Published public private(set) var reported: BaseSettings?
    /// The settings on screen. Equal to `reported` until the user changes something.
    @Published public var draft: BaseSettings?
    /// The pedal settings as the base last reported them, and the copy on screen.
    @Published public private(set) var reportedPedals: PedalSettings?
    @Published public var draftPedals: PedalSettings?
    /// The wheel's position, -1 at full left lock to 1 at full right lock.
    @Published public private(set) var steering = 0.0
    /// What each pedal is putting out right now, from 0 to 1.
    @Published public private(set) var pedalOutputs: [PedalSettings.Pedal: Double] = [:]

    /// Nil for a model that only shows sample settings.
    private let connection: WheelConnection?
    private var lastSteeringUpdate = Date.distantPast
    /// The wheel reports its position far faster than a screen redraws.
    private static let steeringInterval = 1.0 / 60.0

    public var hasBaseChanges: Bool { draft != nil && draft != reported }
    public var hasPedalChanges: Bool { draftPedals != nil && draftPedals != reportedPedals }
    public var hasChanges: Bool { hasBaseChanges || hasPedalChanges }

    /// The wheel's angle from centre in degrees, from the range the base reports.
    public var steeringDegrees: Double? {
        reported.map { steering * Double($0.steeringRange) / 2 }
    }

    /// Watches for a wheel base and follows it.
    public init() {
        let connection = WheelConnection()
        self.connection = connection
        connection.onConnectionChange = { [weak self] connected in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isConnected = connected
                if !connected {
                    self.reported = nil
                    self.draft = nil
                    self.reportedPedals = nil
                    self.draftPedals = nil
                    self.steering = 0
                    self.pedalOutputs = [:]
                }
            }
        }
        connection.onSettings = { [weak self] settings in
            MainActor.assumeIsolated {
                guard let self else { return }
                // An untouched draft follows the base; an edited one is kept until applied or reverted.
                if self.draft == nil || self.draft == self.reported {
                    self.draft = settings
                }
                self.reported = settings
            }
        }
        connection.onPedalSettings = { [weak self] pedals in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.draftPedals == nil || self.draftPedals == self.reportedPedals {
                    self.draftPedals = pedals
                }
                self.reportedPedals = pedals
            }
        }
        // The steering and pedal callbacks fire together, once per report from the base.
        var latestSteering = 0.0
        connection.onSteering = { latestSteering = $0 }
        connection.onPedals = { [weak self] throttle, brake, clutch in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastSteeringUpdate) >= Self.steeringInterval else { return }
                self.lastSteeringUpdate = Date()
                self.steering = latestSteering
                self.pedalOutputs = [.throttle: throttle, .brake: brake, .clutch: clutch]
            }
        }
        connection.start()
    }

    /// A model with no wheel behind it, for drawing the window with sample settings.
    public init(
        sample settings: BaseSettings?, edited: BaseSettings? = nil, steering: Double = 0, isConnected: Bool = true,
        pedals: PedalSettings? = nil, editedPedals: PedalSettings? = nil, pedalOutputs: [PedalSettings.Pedal: Double] = [:]
    ) {
        connection = nil
        self.isConnected = isConnected
        self.reported = settings
        self.draft = edited ?? settings
        self.reportedPedals = pedals
        self.draftPedals = editedPedals ?? pedals
        self.steering = steering
        self.pedalOutputs = pedalOutputs
    }

    /// Sends what was edited on screen to the base. The base's answer then replaces it.
    public func apply() {
        guard let connection else { return }
        if hasBaseChanges, let draft {
            reported = nil
            self.draft = nil
            connection.apply(draft)
        }
        if hasPedalChanges, let draftPedals {
            reportedPedals = nil
            self.draftPedals = nil
            connection.apply(draftPedals)
        }
    }

    /// Drops the edits and shows the base's settings again.
    public func revert() {
        draft = reported
        draftPedals = reportedPedals
    }
}
