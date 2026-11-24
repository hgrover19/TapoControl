import SwiftUI

/// Full controls for one bulb: power, brightness, and white temperature or colour.
struct BulbCardView: View {
    @EnvironmentObject private var model: AppModel
    let bulb: BulbConfig

    @State private var brightness: Double = 100
    @State private var kelvin: Double = 2700
    @State private var hue: Double = 30
    @State private var saturation: Double = 100
    @State private var colorMode = false
    @State private var editing = false

    init(bulb: BulbConfig) {
        self.bulb = bulb
    }

    private var state: BulbState? { model.states[bulb.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: state?.isOn == true ? "lightbulb.fill" : "lightbulb")
                    .foregroundStyle(state?.isOn == true ? swatch : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bulb.name).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state?.isOn == true },
                    set: { model.send(.power($0), to: bulb) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(state == nil && model.errors[bulb.id] != nil)
            }

            if let error = model.errors[bulb.id] {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state != nil {
                sliderRow(icon: "sun.min", value: $brightness, range: 1...100) {
                    model.send(.brightness(Int(brightness.rounded())), to: bulb)
                }

                Picker("", selection: $colorMode) {
                    Text("White").tag(false)
                    Text("Color").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)

                if colorMode {
                    GradientSlider(value: $hue, range: 0...360, colors: Self.hueColors) { editing = $0; if !$0 { sendColor() } }
                    GradientSlider(value: $saturation, range: 0...100,
                                   colors: [.white, Color(hue: hue / 360, saturation: 1, brightness: 1)]) { editing = $0; if !$0 { sendColor() } }
                } else {
                    GradientSlider(value: $kelvin, range: kelvinRange,
                                   colors: [Color(red: 1, green: 0.62, blue: 0.25), .white, Color(red: 0.75, green: 0.86, blue: 1)]) { editing = $0
                        if !$0 { model.send(.colorTemperature(Int(kelvin.rounded())), to: bulb) }
                    }
                    Text("\(Int(kelvin.rounded())) K").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .onAppear(perform: syncFromState)
        .onChange(of: state) { _, _ in if !editing { syncFromState() } }
    }

    private var subtitle: String {
        guard let state else { return bulb.host }
        let model = state.model ?? "Tapo"
        return state.isOn ? "\(model) · \(state.brightness)%" : "\(model) · off"
    }

    private var kelvinRange: ClosedRange<Double> {
        let low = Double(state?.colorTempMin ?? 2500), high = Double(state?.colorTempMax ?? 6500)
        return low < high ? low...high : 2500...6500
    }

    private var swatch: Color {
        guard let state else { return .yellow }
        return state.isColorMode ? Color(hue: Double(state.hue) / 360, saturation: Double(state.saturation) / 100, brightness: 1) : .yellow
    }

    private func sendColor() {
        model.send(.color(hue: Int(hue.rounded()), saturation: Int(saturation.rounded())), to: bulb)
    }

    private func syncFromState() {
        guard let state else { return }
        brightness = Double(state.brightness)
        colorMode = state.isColorMode
        hue = Double(state.hue)
        saturation = Double(state.saturation)
        if state.colorTemp > 0 { kelvin = Double(state.colorTemp) }
    }

    private func sliderRow(icon: String, value: Binding<Double>, range: ClosedRange<Double>, onCommit: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range) { isEditing in
                editing = isEditing
                if !isEditing { onCommit() }
            }
            Text("\(Int(value.wrappedValue.rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    static let hueColors: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) }
}
