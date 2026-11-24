import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.isConfigured {
                OnboardingView()
            } else if model.showSettings {
                SettingsView()
            } else {
                controls
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { model.popoverOpened() }
        .onDisappear { model.popoverClosed() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Room")
                    .font(.headline)
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Toggle("", isOn: Binding(get: { model.roomIsOn }, set: { model.setRoom(on: $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if model.loginBlocked {
                Label("Paused: the bulb rejected the login. Re-enter it in Settings.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 6) {
                ForEach(LightScene.allCases, id: \.self) { scene in
                    Button {
                        model.apply(scene)
                    } label: {
                        Label(scene.title, systemImage: scene.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            ForEach(model.bulbs) { bulb in
                BulbCardView(bulb: bulb)
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.isConfigured {
                Button {
                    model.showSettings.toggle()
                } label: {
                    Label(model.showSettings ? "Done" : "Settings", systemImage: model.showSettings ? "checkmark" : "gearshape")
                }
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.showSettings)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}
