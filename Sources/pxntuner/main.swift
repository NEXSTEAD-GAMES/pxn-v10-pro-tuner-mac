import Foundation
import WheelLink
import WheelProtocol

// pxntuner get                           print the base's settings
// pxntuner set range=540 damper=40       change base settings, then print what the base reports
// pxntuner pedals                        print the pedal curves
// pxntuner pedals brake=gentle clutch=10,30,60,85 throttle-reverse=0
//                                        change pedal settings, then print what the base reports

let shapeNames = PedalCurve.Shape.allCases.map(\.rawValue).joined(separator: ", ")
let usage = """
usage: pxntuner get
       pxntuner set <setting>=<value> ...
       pxntuner pedals [<pedal>=<curve> | <pedal>-reverse=<0 or 1>] ...
settings: \(BaseSettings.allFields.map { "\($0.key) (\($0.range.lowerBound)-\($0.range.upperBound))" }.joined(separator: ", ")), invert (0 or 1)
pedals: throttle, brake, clutch
curves: \(shapeNames), or four output percentages for 20, 40, 60 and 80 percent travel (for example 10,30,60,85)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

func column(_ text: String) -> String {
    text.padding(toLength: 18, withPad: " ", startingAt: 0)
}

func printSettings(_ settings: BaseSettings) {
    for field in BaseSettings.allFields {
        print("\(column(field.name))\(settings[keyPath: field.keyPath])\(field.unit)   [\(field.key)]")
    }
    print("\(column("Invert forces"))\(settings.invertForceFeedback ? "on" : "off")   [invert]")
    print("\(column("End-stop strength"))\(settings.endStopStrength)   (read only)")
}

func printPedals(_ pedals: PedalSettings) {
    for pedal in PedalSettings.Pedal.allCases {
        let curve = pedals[curve: pedal]
        let points = curve.points
            .map { "\(Int(($0.inputFraction * 100).rounded()))%→\(Int(($0.outputFraction * 100).rounded()))%" }
            .joined(separator: "  ")
        let shape = curve.shape?.rawValue ?? "custom"
        print("\(column(pedal.title))\(points)   (\(shape)\(pedals[reversed: pedal] ? ", reversed" : ""))   [\(pedal.rawValue)]")
    }
    print("\(column("Dual clutch"))mode \(pedals.dualClutchMode), value \(pedals.dualClutchValue)   (read only)")
}

/// Runs the run loop until `received` gives a value, or the wait runs out.
func wait<Value>(seconds: Double, for received: () -> Value?) -> Value? {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if let value = received() { return value }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return received()
}

/// A pedal curve from the command line: a shape's name, or four rising output percentages.
func curve(from text: String, replacing current: PedalCurve) -> PedalCurve {
    if let shape = PedalCurve.Shape(rawValue: text) {
        return current.reshaped(shape)
    }
    let outputs = text.split(separator: ",").compactMap { Int($0) }
    guard outputs.count == PedalCurve.pointCount, outputs.count == text.split(separator: ",").count,
          outputs.allSatisfy({ (0...100).contains($0) }), outputs == outputs.sorted() else {
        fail("a curve is one of \(shapeNames), or four rising percentages from 0 to 100, not \(text)")
    }
    var curve = current
    for (index, output) in outputs.enumerated() {
        curve.points[index].outputFraction = Double(output) / 100
    }
    return curve
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, ["get", "set", "pedals"].contains(command) else { fail(usage) }
let changes: [(name: String, value: String)] = arguments.dropFirst().map { argument in
    let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { fail("not a name=value pair: \(argument)\n\(usage)") }
    return (parts[0], parts[1])
}
if command == "get", !changes.isEmpty { fail(usage) }
if command == "set", changes.isEmpty { fail(usage) }

// Everything on the command line is checked before the wheel is touched.
var baseEdits: [(BaseSettings.Field?, Int)] = []
if command == "set" {
    for change in changes {
        guard let value = Int(change.value) else { fail("\(change.name) takes a number, not \(change.value)") }
        if change.name == "invert" {
            guard value == 0 || value == 1 else { fail("invert takes 0 or 1") }
            baseEdits.append((nil, value))
        } else if let field = BaseSettings.allFields.first(where: { $0.key == change.name }) {
            guard field.range.contains(value) else {
                fail("\(field.key) takes \(field.range.lowerBound) to \(field.range.upperBound), not \(value)")
            }
            baseEdits.append((field, value))
        } else {
            fail("unknown setting: \(change.name)\n\(usage)")
        }
    }
}
if command == "pedals" {
    for change in changes {
        let name = change.name.hasSuffix("-reverse") ? String(change.name.dropLast("-reverse".count)) : change.name
        guard PedalSettings.Pedal(rawValue: name) != nil else { fail("unknown pedal: \(change.name)\n\(usage)") }
        if change.name.hasSuffix("-reverse") {
            guard change.value == "0" || change.value == "1" else { fail("\(change.name) takes 0 or 1") }
        } else {
            _ = curve(from: change.value, replacing: PedalCurve(shape: .linear))
        }
    }
}

let connection = WheelConnection()
var latestSettings: BaseSettings?
var latestPedals: PedalSettings?
connection.onSettings = { latestSettings = $0 }
connection.onPedalSettings = { latestPedals = $0 }
connection.start()

switch command {
case "pedals":
    guard var pedals = wait(seconds: 3, for: { latestPedals }) else { fail("no PXN V10 Pro answered") }
    if !changes.isEmpty {
        for change in changes {
            if change.name.hasSuffix("-reverse") {
                let pedal = PedalSettings.Pedal(rawValue: String(change.name.dropLast("-reverse".count)))!
                pedals[reversed: pedal] = change.value == "1"
            } else {
                let pedal = PedalSettings.Pedal(rawValue: change.name)!
                pedals[curve: pedal] = curve(from: change.value, replacing: pedals[curve: pedal])
            }
        }
        latestPedals = nil
        connection.apply(pedals)
        guard let reported = wait(seconds: 3, for: { latestPedals }) else { fail("the base did not confirm the change") }
        pedals = reported
    }
    printPedals(pedals)
default:
    guard var settings = wait(seconds: 3, for: { latestSettings }) else { fail("no PXN V10 Pro answered") }
    if command == "set" {
        for (field, value) in baseEdits {
            if let field {
                settings[keyPath: field.keyPath] = value
            } else {
                settings.invertForceFeedback = value == 1
            }
        }
        latestSettings = nil
        connection.apply(settings)
        guard let reported = wait(seconds: 3, for: { latestSettings }) else { fail("the base did not confirm the change") }
        settings = reported
    }
    printSettings(settings)
}
