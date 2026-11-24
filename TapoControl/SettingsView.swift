import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: [BulbConfig] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bulbs").font(.headline)
            ForEach($draft) { $bulb in
                HStack {
                    TextField("Name", text: $bulb.name)
                        .textFieldStyle(.roundedBorder)
                    TextField("IP address", text: $bulb.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
            HStack {
                Text("Reserve these IPs in your router so they don't change.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") { model.saveBulbs(draft.map(trimmed)) }
                    .disabled(draft == model.bulbs)
            }

            Divider()

            Text("Account").font(.headline)
            HStack {
                Text("Login stored in: \(model.credentialLocation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Change login…") { model.signOut() }
            }

            Toggle("Launch at login", isOn: $model.launchAtLogin)

            Text("If a bulb can't be reached, check System Settings → Privacy & Security → Local Network and make sure TapoControl is on.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { draft = model.bulbs }
    }

    private func trimmed(_ bulb: BulbConfig) -> BulbConfig {
        var copy = bulb
        copy.name = bulb.name.trimmingCharacters(in: .whitespaces)
        copy.host = bulb.host.trimmingCharacters(in: .whitespaces)
        return copy
    }
}
