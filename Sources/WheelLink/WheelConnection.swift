import Foundation
import IOKit.hid
import WheelProtocol

/// The USB link to a PXN V10 Pro wheel base.
///
/// The base has two interfaces this uses: its vendor interface, which carries the settings, and its
/// joystick interface, read here only for where the wheel and pedals are. Callbacks arrive on the run loop
/// of the thread that called `start`.
public final class WheelConnection {
    public static let vendorID = 0x36E6
    public static let productID = 0x400B

    /// True once the base's settings interface is connected.
    public private(set) var isConnected = false

    public var onConnectionChange: ((Bool) -> Void)?
    /// The base's settings, each time it reports them: after connecting, and after every `apply`.
    public var onSettings: ((BaseSettings) -> Void)?
    /// The base's pedal settings, each time it reports them.
    public var onPedalSettings: ((PedalSettings) -> Void)?
    /// The wheel's position, from -1 at full left lock to 1 at full right lock.
    public var onSteering: ((Double) -> Void)?
    /// What the pedals are putting out, each from 0 to 1, after the base has applied their curves.
    public var onPedals: ((_ throttle: Double, _ brake: Double, _ clutch: Double) -> Void)?

    private var manager: IOHIDManager?
    private var settingsDevice: IOHIDDevice?
    private var steeringDevice: IOHIDDevice?
    private let settingsBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let steeringBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    /// Packets waiting to go out. They are sent one at a time with a short gap, so the base is never
    /// handed a second packet while it is still answering the first.
    private var outgoing: [[UInt8]] = []
    private var sendTimer: Timer?
    private static let sendInterval = 0.02

    private static let vendorUsagePage = 0xFF00
    private static let vendorUsage = 1
    private static let joystickReportID: UInt32 = 1
    private static let joystickAxisRange = 32767.0
    /// Where each pedal's 16-bit axis sits in the joystick report: Z, Rz and the slider.
    private static let throttleOffset = 5
    private static let brakeOffset = 11
    private static let clutchOffset = 13
    private static let joystickReportLength = 15

    public init() {}

    deinit {
        stop()
        settingsBuffer.deallocate()
        steeringBuffer.deallocate()
    }

    /// Starts watching for the base on the current thread's run loop.
    public func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Only these two interfaces: the base also has a keyboard interface, which is left alone.
        let interfaces = [
            Self.matching(page: Self.vendorUsagePage, usage: Self.vendorUsage),
            Self.matching(page: kHIDPage_GenericDesktop, usage: kHIDUsage_GD_Joystick),
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, interfaces as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<WheelConnection>.fromOpaque(context!).takeUnretainedValue().matched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<WheelConnection>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        settingsDevice = nil
        steeringDevice = nil
        isConnected = false
        outgoing.removeAll()
        sendTimer?.invalidate()
        sendTimer = nil
    }

    /// Asks the base for its settings; the answer arrives through `onSettings`.
    public func requestSettings() {
        send(BaseSettings.queryPacket)
    }

    /// Asks the base for its pedal settings; the answer arrives through `onPedalSettings`.
    public func requestPedalSettings() {
        send(PedalSettings.queryPacket)
    }

    /// Sets the base to these settings, then asks what it now holds: `onSettings` reports the base's own
    /// answer, not what was asked for.
    public func apply(_ settings: BaseSettings) {
        send(settings.writePacket())
        requestSettings()
    }

    /// Sets the base's pedal settings, then asks what it now holds, as `apply` does for the base settings.
    public func apply(_ pedals: PedalSettings) {
        send(pedals.writePacket())
        requestPedalSettings()
    }

    private func send(_ packet: [UInt8]) {
        guard settingsDevice != nil else { return }
        outgoing.append(packet)
        guard sendTimer == nil else { return }
        sendNext()
        sendTimer = Timer.scheduledTimer(withTimeInterval: Self.sendInterval, repeats: true) { [weak self] _ in
            self?.sendNext()
        }
    }

    private func sendNext() {
        guard let settingsDevice, !outgoing.isEmpty else {
            sendTimer?.invalidate()
            sendTimer = nil
            return
        }
        let packet = outgoing.removeFirst()
        var report = [UInt8](repeating: 0, count: BaseSettings.reportLength)
        report.replaceSubrange(0..<packet.count, with: packet)
        IOHIDDeviceSetReport(settingsDevice, kIOHIDReportTypeOutput, CFIndex(BaseSettings.reportID), report, report.count)
    }

    private func matched(_ device: IOHIDDevice) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int
        if page == Self.vendorUsagePage, settingsDevice == nil {
            settingsDevice = device
            IOHIDDeviceRegisterInputReportCallback(device, settingsBuffer, 64, { context, _, _, _, _, report, length in
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                Unmanaged<WheelConnection>.fromOpaque(context!).takeUnretainedValue().settingsReport(bytes)
            }, context)
            isConnected = true
            onConnectionChange?(true)
            requestSettings()
            requestPedalSettings()
        } else if page == kHIDPage_GenericDesktop, steeringDevice == nil {
            steeringDevice = device
            IOHIDDeviceRegisterInputReportCallback(device, steeringBuffer, 64, { context, _, _, _, reportID, report, length in
                guard reportID == WheelConnection.joystickReportID, length >= WheelConnection.joystickReportLength else { return }
                let x = Int16(bitPattern: UInt16(report[1]) | UInt16(report[2]) << 8)
                let connection = Unmanaged<WheelConnection>.fromOpaque(context!).takeUnretainedValue()
                connection.onSteering?(max(-1, min(1, Double(x) / WheelConnection.joystickAxisRange)))
                func axis(_ offset: Int) -> Double {
                    Double(UInt16(report[offset]) | UInt16(report[offset + 1]) << 8) / Double(UInt16.max)
                }
                connection.onPedals?(axis(WheelConnection.throttleOffset), axis(WheelConnection.brakeOffset),
                                     axis(WheelConnection.clutchOffset))
            }, context)
        }
    }

    private func removed(_ device: IOHIDDevice) {
        if device === settingsDevice {
            settingsDevice = nil
            isConnected = false
            outgoing.removeAll()
            onConnectionChange?(false)
        } else if device === steeringDevice {
            steeringDevice = nil
        }
    }

    private func settingsReport(_ bytes: [UInt8]) {
        if let settings = BaseSettings(reply: bytes) {
            onSettings?(settings)
        } else if let pedals = PedalSettings(reply: bytes) {
            onPedalSettings?(pedals)
        }
    }

    private static func matching(page: Int, usage: Int) -> [String: Int] {
        [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID,
         kIOHIDPrimaryUsagePageKey: page, kIOHIDPrimaryUsageKey: usage]
    }
}
