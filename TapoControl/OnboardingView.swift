import SwiftUI

/// One-time login. The password is turned into KLAP hashes and discarded.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your Tapo bulbs")
                .font(.headline)
            Text("Enter the email and password of your Tapo account. TapoControl checks them against a bulb, keeps only a derived key, and never stores the password.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Tapo email", text: $email)
                .textContentType(.username)
                .textFieldStyle(.roundedBorder)
            SecureField("Tapo password", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)

            Text("Third-Party Compatibility must be on in the Tapo app (Me → Third-Party Services).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let warning {
                Text(warning).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || email.isEmpty || password.isEmpty)
            }
        }
    }

    private func connect() {
        guard !email.isEmpty, !password.isEmpty, !working else { return }
        working = true
        error = nil
        warning = nil
        let (user, pass) = (email.trimmingCharacters(in: .whitespaces), password)
        Task {
            do {
                warning = try await model.signIn(email: user, password: pass)
                password = ""
                model.popoverOpened()
            } catch {
                self.error = ErrorText.message(for: error)
            }
            working = false
        }
    }
}
