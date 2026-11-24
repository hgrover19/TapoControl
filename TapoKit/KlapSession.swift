import CryptoKit
import Foundation

public enum KlapError: Error, Equatable, Sendable {
    /// Network-level failure (bulb off, wrong IP, or Local Network access denied).
    case unreachable(host: String, code: Int, message: String)
    /// The device's handshake1 hash didn't match: wrong email/password. Never retried.
    case badCredentials
    /// The device answered the handshake with a non-200 status (e.g. 403 when it has
    /// switched to TPAP because Third-Party Compatibility is off).
    case handshakeRejected(status: Int)
    case httpStatus(Int)
    case deviceError(code: Int)
    case badResponse(String)
    case crypto(Int)
    case invalidHost(String)
    /// Session cookie or seq no longer accepted; handled internally by re-handshaking once.
    case sessionExpired
}

/// One authenticated KLAP session with one device.
///
/// Requests are serialized so the device sees seq numbers in order. A session is
/// re-established when its TIMEOUT cookie is about to lapse or the device reports an
/// expired session — but never after a credential mismatch (repeated bad logins can
/// lock the device).
public actor KlapSession {
    public let host: String
    private let auth: KlapAuth
    private let urlSession: URLSession
    private let terminalUUID: String

    private var cipher: KlapCipher?
    private var cookie: String?
    private var expiresAt: Date = .distantPast
    private var version: KlapVersion = .v2

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(host: String, auth: KlapAuth, timeout: TimeInterval = 4) {
        self.host = host
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: config)
        terminalUUID = Data(Insecure.MD5.hash(data: Data(UUID().uuidString.utf8))).base64EncodedString()
    }

    /// Sends one SMART request (e.g. `get_device_info`) and returns its `result` object.
    public func request(_ method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        await acquire()
        defer { release() }
        if cipher == nil || Date() >= expiresAt {
            try await handshake()
        }
        do {
            return try await send(method, params: params)
        } catch KlapError.sessionExpired {
            try await handshake()
            return try await send(method, params: params)
        }
    }

    /// Runs the two-step handshake only. Used to verify credentials during onboarding.
    public func verify() async throws {
        await acquire()
        defer { release() }
        try await handshake()
    }

    // MARK: - Handshake

    private func handshake() async throws {
        cipher = nil
        cookie = nil
        let localSeed = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })

        let (reply1, response1) = try await post("handshake1", body: localSeed, cookie: nil)
        guard response1.statusCode == 200 else { throw KlapError.handshakeRejected(status: response1.statusCode) }
        guard reply1.count == 48 else { throw KlapError.badResponse("handshake1 returned \(reply1.count) bytes, expected 48") }
        let remoteSeed = Data(Array(reply1.prefix(16)))
        let serverHash = Data(Array(reply1.suffix(32)))

        // Work out which hash variant the device used. Stop here on a mismatch: the
        // device can't count a failed login until handshake2, so nothing is sent.
        let chosen: (KlapVersion, Data)
        if KlapHash.handshake1(.v2, localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v2) == serverHash {
            chosen = (.v2, auth.v2)
        } else if KlapHash.handshake1(.v1, localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v1) == serverHash {
            chosen = (.v1, auth.v1)
        } else {
            throw KlapError.badCredentials
        }

        let cookies = Self.parseCookies(response1.value(forHTTPHeaderField: "Set-Cookie"))
        guard let sessionID = cookies["TP_SESSIONID"] else { throw KlapError.badResponse("handshake1 sent no TP_SESSIONID cookie") }
        let sessionCookie = "TP_SESSIONID=\(sessionID)"
        let timeout = cookies["TIMEOUT"].flatMap(Double.init) ?? 86_400

        let proof = KlapHash.handshake2(chosen.0, localSeed: localSeed, remoteSeed: remoteSeed, authHash: chosen.1)
        let (_, response2) = try await post("handshake2", body: proof, cookie: sessionCookie)
        guard response2.statusCode == 200 else { throw KlapError.handshakeRejected(status: response2.statusCode) }

        version = chosen.0
        cookie = sessionCookie
        cipher = KlapCipher(localSeed: localSeed, remoteSeed: remoteSeed, authHash: chosen.1)
        // python-kasa renews 20 minutes before the device's TIMEOUT.
        expiresAt = Date().addingTimeInterval(max(60, timeout - 20 * 60))
    }

    // MARK: - Requests

    private func send(_ method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard var current = cipher, let cookie else { throw KlapError.sessionExpired }
        var payload: [String: Any] = [
            "method": method,
            "request_time_milis": Int(Date().timeIntervalSince1970 * 1000),
            "terminal_uuid": terminalUUID,
        ]
        if let params { payload["params"] = params }
        let json = try JSONSerialization.data(withJSONObject: payload)
        let (body, seq) = try current.encrypt(json)
        cipher = current

        let (reply, response) = try await post("request", body: body, cookie: cookie, query: "seq=\(seq)")
        switch response.statusCode {
        case 200: break
        case 401, 403: throw KlapError.sessionExpired
        default: throw KlapError.httpStatus(response.statusCode)
        }
        let plain = try current.decrypt(reply, seq: seq)
        guard let object = try JSONSerialization.jsonObject(with: plain) as? [String: Any] else {
            throw KlapError.badResponse("Reply was not a JSON object")
        }
        let code = (object["error_code"] as? Int) ?? -1
        switch code {
        case 0: return (object["result"] as? [String: Any]) ?? [:]
        case 9999, -40401: throw KlapError.sessionExpired  // SESSION_TIMEOUT_ERROR, SESSION_EXPIRED
        default: throw KlapError.deviceError(code: code)
        }
    }

    private func post(_ path: String, body: Data, cookie: String?, query: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var text = "http://\(host)/app/\(path)"
        if let query { text += "?\(query)" }
        guard let url = URL(string: text) else { throw KlapError.invalidHost(host) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw KlapError.badResponse("Not an HTTP response") }
            return (data, http)
        } catch let error as URLError {
            throw KlapError.unreachable(host: host, code: error.code.rawValue, message: error.localizedDescription)
        }
    }

    /// Parses `TP_SESSIONID=…;TIMEOUT=86400`-style headers into a dictionary.
    public static func parseCookies(_ header: String?) -> [String: String] {
        guard let header else { return [:] }
        var result: [String: String] = [:]
        for part in header.split(whereSeparator: { $0 == ";" || $0 == "," }) {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, !pair[0].isEmpty { result[pair[0]] = pair[1] }
        }
        return result
    }

    // MARK: - Serialization

    private func acquire() async {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// The derived secrets stored instead of the password.
public struct KlapAuth: Codable, Equatable, Sendable {
    public let v2: Data
    public let v1: Data

    public init(v2: Data, v1: Data) {
        self.v2 = v2
        self.v1 = v1
    }

    public init(username: String, password: String) {
        v2 = KlapHash.authHashV2(username: username, password: password)
        v1 = KlapHash.authHashV1(username: username, password: password)
    }

    /// Short identifier for cache keys; not secret-equivalent.
    public var fingerprint: String {
        KlapHash.sha256(v2).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
