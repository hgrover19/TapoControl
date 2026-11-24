import Foundation

enum AppConstants {
    static let keychainService = "com.harshgrover.TapoControl.klap"
}

struct BulbConfig: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var host: String

    static let defaults: [BulbConfig] = [
        BulbConfig(id: "bulb-a", name: "Bulb A", host: "192.168.2.20"),
        BulbConfig(id: "bulb-b", name: "Bulb B", host: "192.168.2.18"),
    ]
}

/// Bulb settings and last-known state, in the app's own preferences.
enum BulbStore {
    private static let bulbsKey = "bulbs.v1"
    private static let statesKey = "states.v1"
    private static let errorsKey = "errors.v1"
    private static let credentialsRejectedKey = "credentialsRejected.v1"

    private static var defaults: UserDefaults { .standard }

    static var bulbs: [BulbConfig] {
        get { decode([BulbConfig].self, key: bulbsKey) ?? BulbConfig.defaults }
        set { encode(newValue, key: bulbsKey) }
    }

    static var states: [String: BulbState] {
        get { decode([String: BulbState].self, key: statesKey) ?? [:] }
        set { encode(newValue, key: statesKey) }
    }

    /// Last error text per bulb id.
    static var errors: [String: String] {
        get { decode([String: String].self, key: errorsKey) ?? [:] }
        set { encode(newValue, key: errorsKey) }
    }

    /// Set after the device rejects the stored login. Blocks further attempts until the
    /// user re-enters it, so a wrong password can't lock the bulbs.
    static var credentialsRejected: Bool {
        get { defaults.bool(forKey: credentialsRejectedKey) }
        set { defaults.set(newValue, forKey: credentialsRejectedKey) }
    }

    static func update(state: BulbState?, error: String?, for id: String) {
        var allStates = states
        if let state { allStates[id] = state }
        states = allStates
        var allErrors = errors
        allErrors[id] = error
        errors = allErrors
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
