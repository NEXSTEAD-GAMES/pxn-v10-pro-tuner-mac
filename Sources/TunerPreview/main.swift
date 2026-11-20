import AppKit
import SwiftUI
import TunerUI
import WheelProtocol

// Draws the window into PNG files with sample settings, so its look can be checked and the README's
// picture made without a wheel connected:  swift run TunerPreview <folder>

@MainActor
func render(_ model: WheelModel, page: TunerView.Page = .base, appearance: NSAppearance.Name, to url: URL) throws {
    let hosting = NSHostingView(rootView: TunerView(page: page).environmentObject(model))
    let size = hosting.fittingSize
    // No title bar: the view already leaves room for one, as it does under the app's hidden title bar.
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    // One turn of the run loop lets SwiftUI finish laying out and drawing.
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))

    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
    print("wrote \(url.path) (\(Int(size.width))×\(Int(size.height)))")
}

@MainActor
func main() throws {
    guard CommandLine.arguments.count == 2 else {
        FileHandle.standardError.write("usage: TunerPreview <folder>\n".data(using: .utf8)!)
        exit(2)
    }
    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    _ = NSApplication.shared

    let base = BaseSettings(
        steeringRange: 540, gameForceFeedback: 90, spring: 100, damper: 100, sineWave: 100, maxTorque: 100,
        mechanicalCentering: 0, mechanicalDamping: 10, roadDetail: 100, invertForceFeedback: false,
        endStopStrength: 1, gameFriction: 100)
    var edited = base
    edited.steeringRange = 900
    edited.damper = 40
    edited.mechanicalDamping = 25

    try render(WheelModel(sample: base, steering: -0.18), appearance: .aqua, to: folder.appendingPathComponent("connected-light.png"))
    try render(WheelModel(sample: base, steering: -0.18), appearance: .darkAqua, to: folder.appendingPathComponent("connected-dark.png"))
    try render(WheelModel(sample: base, edited: edited, steering: 0.42), appearance: .darkAqua, to: folder.appendingPathComponent("edited-dark.png"))
    try render(WheelModel(sample: nil, isConnected: false), appearance: .aqua, to: folder.appendingPathComponent("disconnected-light.png"))

    let pedals = PedalSettings(
        throttle: PedalCurve(shape: .linear), brake: PedalCurve(shape: .gentle), clutch: PedalCurve(shape: .quick),
        throttleReversed: false, brakeReversed: false, clutchReversed: false, dualClutchMode: 2, dualClutchValue: 50)
    let outputs: [PedalSettings.Pedal: Double] = [.throttle: 0.62, .brake: 0.18, .clutch: 0]
    for (appearance, name) in [(NSAppearance.Name.darkAqua, "pedals-dark.png"), (.aqua, "pedals-light.png")] {
        try render(WheelModel(sample: base, steering: 0.05, pedals: pedals, pedalOutputs: outputs),
                   page: .pedals, appearance: appearance, to: folder.appendingPathComponent(name))
    }
}

try MainActor.assumeIsolated { try main() }
