import XCTest
@testable import WheelProtocol

final class PedalSettingsTests: XCTestCase {
    /// A PXN V10 Pro's answer to the pedal settings query, as captured from the base: throttle and brake
    /// linear, the clutch on a quick-start curve, dual clutch 2 and 50, nothing reversed.
    static let reply: [UInt8] = [
        0x01, 0x81, 0xE0, 0x23,
        0x33, 0x33, 0x33, 0x33, 0x66, 0x66, 0x66, 0x66, 0x99, 0x99, 0x99, 0x99, 0xCC, 0xCC, 0xCC, 0xCC,
        0x33, 0x33, 0x33, 0x33, 0x66, 0x66, 0x66, 0x66, 0x99, 0x99, 0x99, 0x99, 0xCC, 0xCC, 0xCC, 0xCC,
        0x33, 0x33, 0x28, 0x5C, 0x66, 0x66, 0xD6, 0xA3, 0x99, 0x99, 0x09, 0xD7, 0xCC, 0xCC, 0xC1, 0xF5,
        0x02, 0x32, 0x00, 0x00, 0x00,
    ] + [UInt8](repeating: 0, count: 6)

    func testReadsTheCapturedReply() throws {
        let pedals = try XCTUnwrap(PedalSettings(reply: Self.reply))

        XCTAssertEqual(pedals.throttle, PedalCurve(shape: .linear))
        XCTAssertEqual(pedals.brake, PedalCurve(shape: .linear))
        XCTAssertEqual(pedals.clutch.points.map(\.input), [0x3333, 0x6666, 0x9999, 0xCCCC])
        XCTAssertEqual(pedals.clutch.points.map(\.output), [0x5C28, 0xA3D6, 0xD709, 0xF5C1])
        XCTAssertEqual(pedals.dualClutchMode, 2)
        XCTAssertEqual(pedals.dualClutchValue, 50)
        XCTAssertFalse(pedals.throttleReversed || pedals.brakeReversed || pedals.clutchReversed)
    }

    func testWritingBackWhatWasReadChangesNothingButTheHeader() throws {
        let pedals = try XCTUnwrap(PedalSettings(reply: Self.reply))

        let packet = pedals.writePacket()
        XCTAssertEqual(Array(packet[0..<4]), [0x01, 0x41, 0xE0, 0x23])
        XCTAssertEqual(Array(packet[4...]), Array(Self.reply[4..<57]))
    }

    func testEverySettingSurvivesAWriteAndARead() {
        let pedals = PedalSettings(
            throttle: PedalCurve(shape: .gentle), brake: PedalCurve(shape: .smooth), clutch: PedalCurve(shape: .quick),
            throttleReversed: true, brakeReversed: false, clutchReversed: true, dualClutchMode: 1, dualClutchValue: 73)
        var echoed = pedals.writePacket()
        echoed.replaceSubrange(0..<4, with: PedalSettings.queryPacket)

        XCTAssertEqual(PedalSettings(reply: echoed), pedals)
    }

    func testOtherReportsAreNotPedalSettings() {
        XCTAssertNil(PedalSettings(reply: BaseSettingsTests.reply), "the base settings reply")
        XCTAssertNil(PedalSettings(reply: Array(Self.reply.prefix(40))), "cut short")
        XCTAssertNil(BaseSettings(reply: Self.reply), "and the pedal reply is not base settings")
    }

    /// The clutch curve the base came with is the quick-start shape, to within its own rounding.
    func testTheCapturedClutchCurveIsTheQuickStartShape() throws {
        let clutch = try XCTUnwrap(PedalSettings(reply: Self.reply)).clutch
        let quick = PedalCurve(shape: .quick)

        for (captured, shaped) in zip(clutch.points, quick.points) {
            XCTAssertEqual(captured.input, shaped.input)
            XCTAssertEqual(Int(captured.output), Int(shaped.output), accuracy: 2)
        }
        XCTAssertEqual(clutch.shape, .quick)
    }

    func testACurveIsNamedOnlyWhenItIsAShape() {
        for shape in PedalCurve.Shape.allCases {
            XCTAssertEqual(PedalCurve(shape: shape).shape, shape)
        }
        var own = PedalCurve(shape: .linear)
        own.setOutput(0.3, at: 0)
        XCTAssertNil(own.shape)
    }

    func testAPointStaysBetweenItsNeighbours() {
        var curve = PedalCurve(shape: .linear)   // outputs 0.2, 0.4, 0.6, 0.8

        curve.setOutput(0.9, at: 1)
        XCTAssertEqual(curve.points[1].outputFraction, 0.6, accuracy: 0.0001, "held at the next point")
        curve.setOutput(0.05, at: 1)
        XCTAssertEqual(curve.points[1].outputFraction, 0.2, accuracy: 0.0001, "held at the previous point")
        curve.setOutput(1.5, at: 3)
        XCTAssertEqual(curve.points[3].outputFraction, 1, accuracy: 0.0001, "the last point stops at full output")
        curve.setOutput(-1, at: 0)
        XCTAssertEqual(curve.points[0].outputFraction, 0, accuracy: 0.0001, "the first point stops at none")
    }

    func testOutputFollowsStraightLinesBetweenThePoints() {
        let linear = PedalCurve(shape: .linear)
        for travel in [0.0, 0.1, 0.2, 0.37, 0.5, 0.8, 0.93, 1.0] {
            XCTAssertEqual(linear.output(at: travel), travel, accuracy: 0.0001)
        }

        let quick = PedalCurve(shape: .quick)   // 0.36 at 20 percent travel, 0.64 at 40 percent
        XCTAssertEqual(quick.output(at: 0.1), 0.18, accuracy: 0.0001)
        XCTAssertEqual(quick.output(at: 0.3), 0.5, accuracy: 0.0001)
        XCTAssertEqual(quick.output(at: 1.0), 1, accuracy: 0.0001)
    }

    func testReshapingKeepsTheTravelPositions() {
        var curve = PedalCurve(shape: .linear)
        curve.points[0].input = 5000

        let reshaped = curve.reshaped(.gentle)
        XCTAssertEqual(reshaped.points.map(\.input), curve.points.map(\.input))
        XCTAssertEqual(reshaped.points[1].outputFraction, 0.16, accuracy: 0.0001)
    }
}
