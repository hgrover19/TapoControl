import Foundation

/// A bulb's state as reported by `get_device_info`.
public struct BulbState: Codable, Equatable, Sendable {
    public var isOn: Bool
    public var brightness: Int      // 1–100 %
    public var hue: Int             // 0–360 °
    public var saturation: Int      // 0–100 %
    public var colorTemp: Int       // Kelvin; 0 means the bulb is in colour (hue/saturation) mode
    public var colorTempMin: Int
    public var colorTempMax: Int
    public var model: String?
    public var nickname: String?
    public var firmware: String?
    public var updatedAt: Date

    public init(isOn: Bool, brightness: Int, hue: Int = 0, saturation: Int = 0, colorTemp: Int = 2700,
                colorTempMin: Int = 2500, colorTempMax: Int = 6500, model: String? = nil,
                nickname: String? = nil, firmware: String? = nil, updatedAt: Date = Date()) {
        self.isOn = isOn
        self.brightness = brightness
        self.hue = hue
        self.saturation = saturation
        self.colorTemp = colorTemp
        self.colorTempMin = colorTempMin
        self.colorTempMax = colorTempMax
        self.model = model
        self.nickname = nickname
        self.firmware = firmware
        self.updatedAt = updatedAt
    }

    public var isColorMode: Bool { colorTemp == 0 }

    /// Builds a state from a `get_device_info` result. Tapo returns the nickname base64-encoded.
    public init(deviceInfo info: [String: Any], now: Date = Date()) throws {
        guard let on = info["device_on"] as? Bool else {
            throw KlapError.badResponse("get_device_info had no device_on field")
        }
        isOn = on
        brightness = (info["brightness"] as? Int) ?? 100
        hue = (info["hue"] as? Int) ?? 0
        saturation = (info["saturation"] as? Int) ?? 0
        colorTemp = (info["color_temp"] as? Int) ?? 0
        if let range = info["color_temp_range"] as? [Int], range.count == 2, range[0] < range[1] {
            colorTempMin = range[0]
            colorTempMax = range[1]
        } else {
            colorTempMin = 2500
            colorTempMax = 6500
        }
        model = info["model"] as? String
        if let encoded = info["nickname"] as? String, let data = Data(base64Encoded: encoded) {
            nickname = String(data: data, encoding: .utf8)
        } else {
            nickname = nil
        }
        firmware = info["fw_ver"] as? String
        updatedAt = now
    }

    /// The state after `command` is applied, used to update the UI before the device confirms.
    public func applying(_ command: LightCommand) -> BulbState {
        var next = self
        next.updatedAt = Date()
        switch command {
        case .power(let on):
            next.isOn = on
        case .brightness(let value):
            next.isOn = true
            next.brightness = value
        case .color(let hue, let saturation):
            next.isOn = true
            next.hue = hue
            next.saturation = saturation
            next.colorTemp = 0
        case .colorTemperature(let kelvin):
            next.isOn = true
            next.colorTemp = kelvin
        case .preset(let on, let brightness, let kelvin):
            next.isOn = on
            if let brightness { next.brightness = brightness }
            if let kelvin { next.colorTemp = kelvin }
        }
        return next
    }
}

/// Commands the app sends, mapped to `set_device_info` params (python-kasa
/// `smart/modules/{brightness,color,colortemperature}.py`).
public enum LightCommand: Equatable, Sendable {
    case power(Bool)
    case brightness(Int)                         // 1–100; use .power(false) for off
    case color(hue: Int, saturation: Int)        // 0–360, 0–100
    case colorTemperature(Int)                   // Kelvin
    case preset(on: Bool, brightness: Int?, colorTemp: Int?)

    public var params: [String: Any] {
        switch self {
        case .power(let on):
            return ["device_on": on]
        case .brightness(let value):
            return ["device_on": true, "brightness": Self.clamp(value, 1, 100)]
        case .color(let hue, let saturation):
            // color_temp must be 0 or it takes precedence over hue/saturation.
            return ["device_on": true, "color_temp": 0,
                    "hue": Self.clamp(hue, 0, 360), "saturation": Self.clamp(saturation, 0, 100)]
        case .colorTemperature(let kelvin):
            return ["device_on": true, "color_temp": kelvin]
        case .preset(let on, let brightness, let kelvin):
            var params: [String: Any] = ["device_on": on]
            if on, let brightness { params["brightness"] = Self.clamp(brightness, 1, 100) }
            if on, let kelvin { params["color_temp"] = kelvin }
            return params
        }
    }

    static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int { min(max(value, low), high) }
}

/// A Tapo light reached over KLAP.
public struct TapoLight: Sendable {
    public let session: KlapSession

    public init(host: String, auth: KlapAuth) {
        session = KlapSession(host: host, auth: auth)
    }

    public func fetchState() async throws -> BulbState {
        try BulbState(deviceInfo: try await session.request("get_device_info"))
    }

    public func send(_ command: LightCommand) async throws {
        _ = try await session.request("set_device_info", params: command.params)
    }
}
