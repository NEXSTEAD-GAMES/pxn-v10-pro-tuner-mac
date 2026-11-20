import SwiftUI
import TunerUI

@main
struct TunerApp: App {
    @StateObject private var model = WheelModel()

    init() {
        // Run from a bare binary (swift run) the app would otherwise start without a Dock icon or focus.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("PXN V10 Pro Tuner", id: "main") {
            TunerView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
