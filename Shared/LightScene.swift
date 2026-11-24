enum LightScene: String, CaseIterable, Sendable {
    case bright, warm, dim, off

    var title: String {
        switch self {
        case .bright: return "Bright"
        case .warm: return "Warm"
        case .dim: return "Dim"
        case .off: return "Off"
        }
    }

    var symbol: String {
        switch self {
        case .bright: return "sun.max.fill"
        case .warm: return "flame.fill"
        case .dim: return "moon.fill"
        case .off: return "power"
        }
    }

    var command: LightCommand {
        switch self {
        case .bright: return .preset(on: true, brightness: 100, colorTemp: 5000)
        case .warm: return .preset(on: true, brightness: 70, colorTemp: 2700)
        case .dim: return .preset(on: true, brightness: 15, colorTemp: 2500)
        case .off: return .power(false)
        }
    }
}
