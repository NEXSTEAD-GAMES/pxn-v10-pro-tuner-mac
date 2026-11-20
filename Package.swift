// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pxn-v10-pro-tuner-mac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TunerApp", targets: ["TunerApp"]),
        .executable(name: "pxntuner", targets: ["pxntuner"]),
    ],
    targets: [
        // The settings packet: what the bytes mean. No hardware access, so it is fully testable.
        .target(name: "WheelProtocol"),
        // The USB connection to the wheel base.
        .target(name: "WheelLink", dependencies: ["WheelProtocol"]),
        // The window and its model.
        .target(name: "TunerUI", dependencies: ["WheelProtocol", "WheelLink"]),
        // The Mac app. Scripts/make-app.sh wraps it into an app bundle.
        .executableTarget(name: "TunerApp", dependencies: ["TunerUI"]),
        // The same settings from a terminal.
        .executableTarget(name: "pxntuner", dependencies: ["WheelProtocol", "WheelLink"]),
        // Developer tool: draws the window with sample settings into PNG files, with no wheel connected.
        .executableTarget(name: "TunerPreview", dependencies: ["TunerUI", "WheelProtocol"]),
        .testTarget(name: "WheelProtocolTests", dependencies: ["WheelProtocol"]),
    ]
)
