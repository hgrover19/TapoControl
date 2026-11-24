import Foundation

enum ServiceError: LocalizedError {
    case notConfigured
    case loginBlocked
    case unknownBulb(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Enter your Tapo login to connect."
        case .loginBlocked: return "Paused after the bulb rejected the login. Re-enter it in Settings."
        case .unknownBulb(let id): return "Unknown bulb \(id)."
        }
    }
}

/// Talks to the bulbs and caches what they report.
final class LightService: @unchecked Sendable {
    static let shared = LightService()

    private let lock = NSLock()
    private var lights: [String: TapoLight] = [:]   // key: host|auth fingerprint

    // MARK: Reading

    /// Fetches every bulb concurrently and caches the results. Errors are cached per bulb.
    @discardableResult
    func refreshAll() async -> [String: BulbState] {
        let bulbs = BulbStore.bulbs
        await withTaskGroup(of: Void.self) { group in
            for bulb in bulbs {
                group.addTask { _ = try? await self.refresh(bulb) }
            }
        }
        return BulbStore.states
    }

    @discardableResult
    func refresh(_ bulb: BulbConfig) async throws -> BulbState {
        do {
            let state = try await light(for: bulb).fetchState()
            BulbStore.update(state: state, error: nil, for: bulb.id)
            return state
        } catch {
            record(error, for: bulb)
            throw error
        }
    }

    // MARK: Writing

    func send(_ command: LightCommand, to bulb: BulbConfig) async throws {
        do {
            try await light(for: bulb).send(command)
            let previous = BulbStore.states[bulb.id] ?? BulbState(isOn: false, brightness: 100)
            BulbStore.update(state: previous.applying(command), error: nil, for: bulb.id)
        } catch {
            record(error, for: bulb)
            throw error
        }
    }

    /// Sends the same command to every bulb at once. Throws the first error after all finish.
    func sendToAll(_ command: LightCommand) async throws {
        let bulbs = BulbStore.bulbs
        let failures: [Error] = await withTaskGroup(of: Error?.self) { group in
            for bulb in bulbs {
                group.addTask {
                    do { try await self.send(command, to: bulb); return nil } catch { return error }
                }
            }
            var errors: [Error] = []
            for await error in group { if let error { errors.append(error) } }
            return errors
        }
        if let first = failures.first { throw first }
    }

    func setRoom(on: Bool) async throws { try await sendToAll(.power(on)) }

    func apply(_ scene: LightScene) async throws { try await sendToAll(scene.command) }

    // MARK: Credentials

    /// Checks a login against the first reachable bulb before saving it.
    /// Returns nil when verified, or a warning when no bulb could be reached.
    func verifyAndSave(username: String, password: String) async throws -> String? {
        let auth = KlapAuth(username: username, password: password)
        var lastUnreachable: Error?
        for bulb in BulbStore.bulbs {
            do {
                try await KlapSession(host: bulb.host, auth: auth).verify()
                try save(auth)
                return nil
            } catch KlapError.unreachable(let host, let code, let message) {
                lastUnreachable = KlapError.unreachable(host: host, code: code, message: message)
                continue
            }
            // badCredentials and handshake rejections propagate: nothing is saved.
        }
        try save(auth)
        return lastUnreachable.map { "Saved, but no bulb answered to confirm the login: \(ErrorText.message(for: $0))" }
    }

    func signOut() {
        CredentialStore.clear()
        resetSessions()
        BulbStore.credentialsRejected = false
    }

    func resetSessions() {
        lock.lock()
        lights.removeAll()
        lock.unlock()
    }

    // MARK: Internals

    private func save(_ auth: KlapAuth) throws {
        try CredentialStore.save(auth)
        BulbStore.credentialsRejected = false
        BulbStore.errors = [:]
        resetSessions()
    }

    private func light(for bulb: BulbConfig) throws -> TapoLight {
        if BulbStore.credentialsRejected { throw ServiceError.loginBlocked }
        guard let auth = CredentialStore.load() else { throw ServiceError.notConfigured }
        let key = "\(bulb.host)|\(auth.fingerprint)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = lights[key] { return existing }
        let created = TapoLight(host: bulb.host, auth: auth)
        lights[key] = created
        return created
    }

    private func record(_ error: Error, for bulb: BulbConfig) {
        if case KlapError.badCredentials = error { BulbStore.credentialsRejected = true }
        BulbStore.update(state: nil, error: ErrorText.message(for: error), for: bulb.id)
    }
}
