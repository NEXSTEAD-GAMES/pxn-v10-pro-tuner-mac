import SwiftUI
import WheelProtocol

/// The whole window: the live wheel and its range on the left, the force settings on the right.
public struct TunerView: View {
    /// The two sets of settings the right-hand side switches between.
    public enum Page: String, CaseIterable, Identifiable {
        case base = "Wheel base"
        case pedals = "Pedals"

        public var id: String { rawValue }
    }

    @EnvironmentObject private var model: WheelModel
    @State private var page: Page

    private static let rangePresets = [360, 540, 900, 1080]
    private static let accent = Color.accentColor

    public init(page: Page = .base) {
        _page = State(initialValue: page)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                wheelPanel
                    .frame(width: 320)
                Divider()
                settingsPanel
            }
            Divider()
            actionBar
        }
        .frame(width: 880, height: 700)
        .background(WindowBackground().ignoresSafeArea())
        .ignoresSafeArea()
    }

    // MARK: - The wheel

    private var wheelPanel: some View {
        VStack(spacing: 0) {
            ConnectionPill(isConnected: model.isConnected)
                .padding(.top, 44)

            Spacer(minLength: 12)

            WheelDial(steering: model.steering, degrees: model.steeringDegrees, tint: Self.accent)

            VStack(spacing: 2) {
                Text(model.steeringDegrees.map { Self.signed($0) } ?? "–")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(model.steeringDegrees == nil ? .tertiary : .primary)
                Text(model.reported.map { "of ±\($0.steeringRange / 2)°" } ?? "wheel position")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            Spacer(minLength: 12)

            rangeControl
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
        .background(.black.opacity(0.04))
    }

    private var rangeControl: some View {
        let field = BaseSettings.steeringRangeField
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(field.name)
                    .font(.headline)
                Spacer()
                Text("\(model.draft?.steeringRange ?? field.range.lowerBound)°")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(model.draft == nil ? .secondary : .primary)
            }
            TunerSlider(value: binding(field), range: Double(field.range.lowerBound)...Double(field.range.upperBound),
                        step: Double(field.step), tint: Self.accent)
            HStack(spacing: 8) {
                ForEach(Self.rangePresets, id: \.self) { degrees in
                    PresetChip(title: "\(degrees)°", isSelected: model.draft?.steeringRange == degrees, tint: Self.accent) {
                        model.draft?.steeringRange = degrees
                    }
                }
            }
        }
        .padding(16)
        .background(CardBackground())
        .disabled(model.draft == nil)
        .help(field.help)
    }

    // MARK: - The settings

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            Picker("Settings", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.top, 14)
            .padding(.bottom, 12)

            switch page {
            case .base: basePage
            case .pedals: pedalsPage
            }
        }
    }

    private var pedalsPage: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(PedalSettings.Pedal.allCases) { pedal in
                        PedalCard(
                            pedal: pedal,
                            curve: Binding(
                                get: { model.draftPedals?[curve: pedal] ?? PedalCurve(shape: .linear) },
                                set: { model.draftPedals?[curve: pedal] = $0 }),
                            isReversed: Binding(
                                get: { model.draftPedals?[reversed: pedal] ?? false },
                                set: { model.draftPedals?[reversed: pedal] = $0 }),
                            liveOutput: model.pedalOutputs[pedal])
                    }
                }
                Text("Drag a point up or down to change how much the pedal gives at that part of its travel. "
                     + "The dot shows where the pedal is now. Dual-clutch settings stay as the base has them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .disabled(model.draftPedals == nil)
            .opacity(model.draftPedals == nil ? 0.35 : 1)

            if model.draftPedals == nil {
                waitingNote
            }
        }
    }

    private var basePage: some View {
        ZStack {
            VStack(spacing: 14) {
                SettingsCard(title: "Force feedback") {
                    ForEach(BaseSettings.forceFields) { row($0) }
                    CardDivider()
                    ToggleRow(title: "Invert forces", symbol: "arrow.left.arrow.right", color: .purple,
                              isOn: Binding(get: { model.draft?.invertForceFeedback ?? false },
                                            set: { model.draft?.invertForceFeedback = $0 }))
                        .help("Reverses the direction of every force.")
                }
                SettingsCard(title: "Game effects") {
                    ForEach(BaseSettings.effectFields) { row($0) }
                }
                SettingsCard(title: "Built into the base") {
                    ForEach(BaseSettings.mechanicalFields) { row($0) }
                    CardDivider()
                    ValueRow(title: "End-stop strength", symbol: "stop.fill", color: .gray,
                             value: model.draft.map { "\($0.endStopStrength)" } ?? "–")
                        .help("Shown as the base reports it. This app does not change it.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .disabled(model.draft == nil)
            .opacity(model.draft == nil ? 0.35 : 1)

            if model.draft == nil {
                waitingNote
            }
        }
    }

    private var waitingNote: some View {
        VStack(spacing: 8) {
            if model.isConnected {
                ProgressView()
                Text("Reading the base's settings")
                    .font(.title3.weight(.medium))
            } else {
                Image(systemName: "cable.connector")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("Connect a PXN V10 Pro")
                    .font(.title3.weight(.medium))
                Text("Powered, in PC mode, over USB.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }

    private func row(_ field: BaseSettings.Field) -> some View {
        let style = FieldStyle.of(field)
        return SliderRow(title: field.name, symbol: style.symbol, color: style.color,
                         value: binding(field), range: Double(field.range.lowerBound)...Double(field.range.upperBound),
                         step: Double(field.step), unit: field.unit)
            .help(field.help)
    }

    // MARK: - Apply

    private var actionBar: some View {
        HStack(spacing: 12) {
            Text("Unofficial. Not affiliated with PXN.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if model.hasChanges {
                Label("Not applied yet", systemImage: "circle.fill")
                    .labelStyle(EditedLabelStyle())
                    .transition(.opacity)
            }
            Button("Revert") { model.revert() }
                .controlSize(.large)
                .disabled(!model.hasChanges)
            Button("Apply") { model.apply() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasChanges)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.15), value: model.hasChanges)
    }

    private func binding(_ field: BaseSettings.Field) -> Binding<Double> {
        Binding(
            get: { Double(model.draft?[keyPath: field.keyPath] ?? field.range.lowerBound) },
            set: { model.draft?[keyPath: field.keyPath] = Int($0.rounded()) })
    }

    private static func signed(_ degrees: Double) -> String {
        let rounded = Int(degrees.rounded())
        return rounded == 0 ? "0°" : (rounded > 0 ? "+\(rounded)°" : "−\(-rounded)°")
    }
}

// MARK: - Pieces

/// Symbol and colour for each setting's icon tile.
private struct FieldStyle {
    let symbol: String
    let color: Color

    static func of(_ field: BaseSettings.Field) -> FieldStyle {
        switch field.key {
        case "force": return FieldStyle(symbol: "bolt.fill", color: .orange)
        case "torque": return FieldStyle(symbol: "gauge.high", color: .red)
        case "spring": return FieldStyle(symbol: "arrow.left.and.right", color: .green)
        case "damper": return FieldStyle(symbol: "drop.fill", color: .blue)
        case "friction": return FieldStyle(symbol: "hand.raised.fill", color: .brown)
        case "vibration": return FieldStyle(symbol: "waveform", color: .pink)
        case "road": return FieldStyle(symbol: "road.lanes", color: .teal)
        case "centring": return FieldStyle(symbol: "scope", color: .indigo)
        case "damping": return FieldStyle(symbol: "wind", color: .cyan)
        default: return FieldStyle(symbol: "slider.horizontal.3", color: .gray)
        }
    }
}

private struct ConnectionPill: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 8, height: 8)
                .shadow(color: isConnected ? .green.opacity(0.7) : .clear, radius: 3)
            Text(isConnected ? "V10 Pro connected" : "Not connected")
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.2), value: isConnected)
    }
}

private struct PresetChip: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(spacing: 10) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(CardBackground())
        }
    }
}

struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

private struct CardDivider: View {
    var body: some View {
        Divider().padding(.leading, 38)
    }
}

/// The small coloured icon tile at the start of each row.
struct IconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white))
    }
}

private struct SliderRow: View {
    let title: String
    let symbol: String
    let color: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color)
            Text(title)
                .frame(width: 122, alignment: .leading)
            TunerSlider(value: $value, range: range, step: step, tint: color)
            Text("\(Int(value))\(unit)")
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let symbol: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color)
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct ValueRow: View {
    let title: String
    let symbol: String
    let color: Color
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color)
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct EditedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(.orange)
            configuration.title
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// The window's own translucent backdrop.
private struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
