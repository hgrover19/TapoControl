import CommonCrypto
import CryptoKit
import Foundation

/// Hash helpers for TP-Link's KLAP protocol.
///
/// Mirrors python-kasa 0.12.0 (`kasa/transports/klaptransport.py`):
/// `KlapTransportV2` for the hashes Tapo bulbs use, `KlapTransport` for the
/// older v1 (MD5-based) variant.
public enum KlapHash {
    public static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    public static func sha1(_ data: Data) -> Data { Data(Insecure.SHA1.hash(data: data)) }
    public static func md5(_ data: Data) -> Data { Data(Insecure.MD5.hash(data: data)) }

    /// v2 auth hash: SHA256(SHA1(username) ‖ SHA1(password)). 32 bytes.
    public static func authHashV2(username: String, password: String) -> Data {
        sha256(sha1(Data(username.utf8)) + sha1(Data(password.utf8)))
    }

    /// v1 auth hash: MD5(MD5(username) ‖ MD5(password)). 16 bytes.
    public static func authHashV1(username: String, password: String) -> Data {
        md5(md5(Data(username.utf8)) + md5(Data(password.utf8)))
    }

    /// Hash the device returns in handshake1, which proves it knows the same credentials.
    public static func handshake1(_ version: KlapVersion, localSeed: Data, remoteSeed: Data, authHash: Data) -> Data {
        switch version {
        case .v2: return sha256(localSeed + remoteSeed + authHash)
        case .v1: return sha256(localSeed + authHash)
        }
    }

    /// Hash the client sends in handshake2.
    public static func handshake2(_ version: KlapVersion, localSeed: Data, remoteSeed: Data, authHash: Data) -> Data {
        switch version {
        case .v2: return sha256(remoteSeed + localSeed + authHash)
        case .v1: return sha256(remoteSeed + authHash)
        }
    }
}

public enum KlapVersion: String, Codable, Sendable {
    case v1, v2
}

/// Per-session encryption state (python-kasa `KlapEncryptionSession`).
public struct KlapCipher: Sendable {
    public let key: Data        // 16 bytes
    public let ivPrefix: Data   // 12 bytes
    public let signature: Data  // 28 bytes
    public private(set) var seq: Int32

    public init(localSeed: Data, remoteSeed: Data, authHash: Data) {
        let material = localSeed + remoteSeed + authHash
        key = Data(Array(KlapHash.sha256(Data("lsk".utf8) + material).prefix(16)))
        let fullIV = Array(KlapHash.sha256(Data("iv".utf8) + material))
        ivPrefix = Data(fullIV[0..<12])
        let tail = UInt32(fullIV[28]) << 24 | UInt32(fullIV[29]) << 16 | UInt32(fullIV[30]) << 8 | UInt32(fullIV[31])
        seq = Int32(bitPattern: tail)
        signature = Data(Array(KlapHash.sha256(Data("ldk".utf8) + material).prefix(28)))
    }

    /// Big-endian signed 32-bit encoding, as python's `struct.pack(">l", seq)`.
    public static func bytes(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    /// Increments seq, then returns `SHA256(sig ‖ seq ‖ ct) ‖ ct` and the seq used.
    public mutating func encrypt(_ plaintext: Data) throws -> (body: Data, seq: Int32) {
        seq = seq &+ 1
        let iv = ivPrefix + Self.bytes(seq)
        let ciphertext = try AESCBC.crypt(encrypt: true, plaintext, key: key, iv: iv)
        let mac = KlapHash.sha256(signature + Self.bytes(seq) + ciphertext)
        return (mac + ciphertext, seq)
    }

    /// Decrypts a device reply sent for request `seq` (drops the 32-byte signature).
    public func decrypt(_ body: Data, seq: Int32) throws -> Data {
        guard body.count > 32 else { throw KlapError.badResponse("Reply too short (\(body.count) bytes)") }
        let iv = ivPrefix + Self.bytes(seq)
        return try AESCBC.crypt(encrypt: false, Data(body.dropFirst(32)), key: key, iv: iv)
    }
}

/// AES-128-CBC with PKCS7 padding through CommonCrypto (CryptoKit has no CBC mode).
enum AESCBC {
    static func crypt(encrypt: Bool, _ input: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let capacity = output.count
        var produced = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outPtr in
            input.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, input.count,
                            outPtr.baseAddress, capacity,
                            &produced
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else { throw KlapError.crypto(Int(status)) }
        output.count = produced
        return output
    }
}
