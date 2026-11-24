import XCTest

/// Byte-for-byte checks against python-kasa 0.12.0 (vectors from tools/gen_vectors.py,
/// fake credentials and fixed seeds).
final class KlapCryptoTests: XCTestCase {
    let username = "user@example.com"
    let password = "hunter2-Test"
    let localSeed = Data(hex: "101112131415161718191a1b1c1d1e1f")
    let remoteSeed = Data(hex: "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf")

    func testAuthHashes() {
        XCTAssertEqual(KlapHash.authHashV2(username: username, password: password).hex,
                       "e872b24b01914528c05121d5400e93a2b598656385a18eb6f2cf8f493663549f")
        XCTAssertEqual(KlapHash.authHashV1(username: username, password: password).hex,
                       "8a874ae4ca5017d0b803d7c96ad0a91f")
    }

    func testHandshakeHashes() {
        let auth = KlapAuth(username: username, password: password)
        XCTAssertEqual(KlapHash.handshake1(.v2, localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v2).hex,
                       "70ad2bc2b136091f326ae9d231ba8f5df59eb049a4ff0de21e6cd28929ccadcd")
        XCTAssertEqual(KlapHash.handshake2(.v2, localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v2).hex,
                       "c4e9efc31a0a931f05ae0ea3a461bca5b62e2ec52f182463a3646b62b71879c5")
        XCTAssertEqual(KlapHash.handshake1(.v1, localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v1).hex,
                       "ddfb56a13a32374c0fd39b20ebcbd00de4c60aeb565142f1fe8e140bb098de5e")
        XCTAssertEqual(KlapHash.handshake2(.v1, localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v1).hex,
                       "82790390565d7b6bdc297a913331a73eae738a031deb94df08039d85a5666c44")
    }

    func testSessionDerivation() {
        let auth = KlapAuth(username: username, password: password)
        let cipher = KlapCipher(localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v2)
        XCTAssertEqual(cipher.key.hex, "8a63f5c039cf94bcfd970a12aeba4019")
        XCTAssertEqual(cipher.ivPrefix.hex, "7c7ee73c252bd4a6a80a0eac")
        XCTAssertEqual(cipher.seq, -768823753)
        XCTAssertEqual(cipher.signature.hex, "9596bf9ae44f2074281693af1ffcc594c9aec84176c8eef2be31dd22")
    }

    func testEncryptMatchesPythonKasa() throws {
        let auth = KlapAuth(username: username, password: password)
        var cipher = KlapCipher(localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v2)
        let request = #"{"method":"get_device_info","request_time_milis":1700000000000,"terminal_uuid":"dGVzdA=="}"#
        let (body, seq) = try cipher.encrypt(Data(request.utf8))
        XCTAssertEqual(seq, -768823752)
        XCTAssertEqual(body.hex, "16e60b4e81f3f3092e80f6c0b4af8b5657a5edbfbfc7f4b9591fc33584264f769681facfc943b0ea972dc98ea765e99b6293cfcd7ab38abf2384bf7910dc406e5ec3b0c87a9bb92423e8af6fe7261f0e1fa9de52a6fd278409f50d2025abc80a35a17f08d3fc912921f3cd1530a1ec7c23bbd2f8753c45c47c599ce713eb73b8")
    }

    func testDecryptDeviceReply() throws {
        let auth = KlapAuth(username: username, password: password)
        let cipher = KlapCipher(localSeed: localSeed, remoteSeed: remoteSeed, authHash: auth.v2)
        let reply = Data(hex: "15957623f134cf98c8c5a5d63d37c2c3966d8071dd5beef7fd43e53581edf675be5954d97ee7a9d472741209d77a3df01b218d5fedcc83f6b1d92cf6fc76add5cfbcbd17ee9377a3f861701f4d698ab99ff7eabf6a1a414fe98871e3743c76ce")
        let plain = try cipher.decrypt(reply, seq: -768823752)
        XCTAssertEqual(String(data: plain, encoding: .utf8), #"{"error_code":0,"result":{"device_on":true,"brightness":42}}"#)
    }

    func testCookieParsing() {
        let cookies = KlapSession.parseCookies("TP_SESSIONID=ABCDEF0123;TIMEOUT=86400")
        XCTAssertEqual(cookies["TP_SESSIONID"], "ABCDEF0123")
        XCTAssertEqual(cookies["TIMEOUT"], "86400")
        XCTAssertEqual(KlapSession.parseCookies(nil), [:])
    }
}

final class LightModelTests: XCTestCase {
    func testDeviceInfoParsing() throws {
        let info: [String: Any] = [
            "device_on": true, "brightness": 55, "hue": 120, "saturation": 80, "color_temp": 0,
            "color_temp_range": [2500, 6500], "model": "L530", "fw_ver": "1.1.10 Build 230913",
            "nickname": Data("Desk Lamp".utf8).base64EncodedString(),
        ]
        let state = try BulbState(deviceInfo: info)
        XCTAssertTrue(state.isOn)
        XCTAssertEqual(state.brightness, 55)
        XCTAssertTrue(state.isColorMode)
        XCTAssertEqual(state.nickname, "Desk Lamp")
        XCTAssertEqual(state.model, "L530")
    }

    func testCommandParams() {
        XCTAssertEqual(LightCommand.power(false).params["device_on"] as? Bool, false)
        XCTAssertEqual(LightCommand.brightness(0).params["brightness"] as? Int, 1)
        XCTAssertEqual(LightCommand.brightness(250).params["brightness"] as? Int, 100)
        let color = LightCommand.color(hue: 400, saturation: 50).params
        XCTAssertEqual(color["color_temp"] as? Int, 0)
        XCTAssertEqual(color["hue"] as? Int, 360)
        let off = LightCommand.preset(on: false, brightness: 50, colorTemp: 2700).params
        XCTAssertEqual(off.count, 1)
    }
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
