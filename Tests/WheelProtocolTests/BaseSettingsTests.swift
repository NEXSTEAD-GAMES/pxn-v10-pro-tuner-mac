import XCTest
@testable import WheelProtocol

final class BaseSettingsTests: XCTestCase {
    /// A PXN V10 Pro's answer to the settings query, as captured from the base.
    static let reply: [UInt8] = [
        0x01, 0x81, 0xE0, 0x22, 0x1C, 0x02, 0x5A, 0x64, 0x64, 0x64, 0x64, 0x64, 0xC8, 0x00, 0x0A, 0x64,
        0x00, 0x00, 0x01, 0x00, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x64, 0x64, 0x00,
    ] + [UInt8](repeating: 0, count: 27)

    /// The write the same base accepted when only its steering range was changed to 900 degrees.
    static let acceptedWrite: [UInt8] = [
        0x01, 0x41, 0xE0, 0x22, 0x84, 0x03, 0x5A, 0x64, 0x64, 0x64, 0x64, 0x64, 0x00, 0x00, 0x0A, 0x64,
        0x00, 0x00, 0x01,
    ] + [UInt8](repeating: 0, count: 15) + [0x64]

    func testReadsTheCapturedReply() throws {
        let settings = try XCTUnwrap(BaseSettings(reply: Self.reply))

        XCTAssertEqual(settings, BaseSettings(
            steeringRange: 540, gameForceFeedback: 90, spring: 100, damper: 100, sineWave: 100, maxTorque: 100,
            mechanicalCentering: 0, mechanicalDamping: 10, roadDetail: 100, invertForceFeedback: false,
            endStopStrength: 1, gameFriction: 100))
    }

    func testWritesThePacketTheBaseAccepted() throws {
        var settings = try XCTUnwrap(BaseSettings(reply: Self.reply))
        settings.steeringRange = 900

        XCTAssertEqual(settings.writePacket(), Self.acceptedWrite)
    }

    func testEverySettingSurvivesAWriteAndARead() {
        let settings = BaseSettings(
            steeringRange: 1080, gameForceFeedback: 71, spring: 12, damper: 34, sineWave: 56, maxTorque: 78,
            mechanicalCentering: 9, mechanicalDamping: 21, roadDetail: 43, invertForceFeedback: true,
            endStopStrength: 2, gameFriction: 65)
        // A reply has the write's layout under the query's header.
        var echoed = settings.writePacket()
        echoed.replaceSubrange(0..<4, with: BaseSettings.queryPacket)

        XCTAssertEqual(BaseSettings(reply: echoed), settings)
    }

    func testOtherReportsAreNotSettings() {
        XCTAssertNil(BaseSettings(reply: [0x01, 0x41, 0xE0, 0x00] + [UInt8](repeating: 0, count: 59)), "write acknowledgement")
        XCTAssertNil(BaseSettings(reply: Array(Self.reply.prefix(20))), "cut short")
        XCTAssertNil(BaseSettings(reply: []), "empty")
    }

    func testWriteKeepsEachValueInsideWhatTheBaseTakes() {
        var settings = BaseSettings(reply: Self.reply)!
        settings.steeringRange = 5000
        settings.maxTorque = 5
        settings.damper = 250
        settings.spring = -3

        let written = settings.clamped()
        XCTAssertEqual(written.steeringRange, 1800)
        XCTAssertEqual(written.maxTorque, 30)
        XCTAssertEqual(written.damper, 100)
        XCTAssertEqual(written.spring, 0)
    }

    func testSteeringRangeIsWrittenInTenDegreeSteps() {
        var settings = BaseSettings(reply: Self.reply)!
        for (asked, written) in [(94, 90), (95, 100), (541, 540), (546, 550), (20, 90)] {
            settings.steeringRange = asked
            XCTAssertEqual(settings.clamped().steeringRange, written, "asked for \(asked)")
        }
    }
}
