import Foundation

/// Turns protocol errors into one-line, actionable messages.
enum ErrorText {
    static func message(for error: Error) -> String {
        switch error {
        case KlapError.badCredentials:
            return "The bulb rejected the Tapo email or password. Re-enter them in Settings."
        case KlapError.handshakeRejected(let status):
            return "The bulb refused the local login (HTTP \(status)). In the Tapo app, go to Me → Third-Party Services and turn Third-Party Compatibility off and on again, with the phone on the same Wi-Fi."
        case KlapError.unreachable(let host, _, let message):
            return "Can't reach \(host) (\(message)). Check the bulb has power and the IP is right, and that TapoControl is allowed under System Settings → Privacy & Security → Local Network."
        case KlapError.deviceError(let code):
            return "The bulb returned error \(code)."
        case KlapError.httpStatus(let status):
            return "The bulb answered with HTTP \(status)."
        case KlapError.badResponse(let detail):
            return "Unexpected reply from the bulb: \(detail)"
        case KlapError.crypto(let status):
            return "Encryption failed (status \(status))."
        case KlapError.invalidHost(let host):
            return "“\(host)” isn't a valid IP address or host name."
        case KlapError.sessionExpired:
            return "The bulb ended the session twice in a row. Try again."
        case let error as LocalizedError:
            return error.errorDescription ?? String(describing: error)
        default:
            return error.localizedDescription
        }
    }
}
