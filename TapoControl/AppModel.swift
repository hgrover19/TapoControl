import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var bulbs: [BulbConfig] = BulbStore.bulbs
    @Published var states: [String: BulbState] = BulbStore.states
    @Published var errors: [String: String] = BulbStore.errors
    @Published var isConfigured: Bool = CredentialStore.load() != nil
    @Published var loginBlocked: Bool = BulbStore.credentialsRejected
    @Published var isRefreshing = false
    @Published var showSettings = false

    private let service = LightService.shared
    private var loopTask: Task<Void, Never>?
    private var popoverVisible = false

    init() {
        // Polls every 5 s while the popover is open and every 30 s otherwise, so the
        // menu bar icon reflects changes made from the phone. The first pass also
        // triggers the Local Network prompt.
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval: Double = self.popoverVisible ? 5 : 30
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    var roomIsOn: Bool { bulbs.contains { states[$0.id]?.isOn == true } }

    // MARK: Popover visibility

    func popoverOpened() {
        popoverVisible = true
        Task { await refresh() }
    }

    func popoverClosed() {
        popoverVisible = false
    }

    func refresh() async {
        guard isConfigured, !loginBlocked else { return }
        isRefreshing = true
        await service.refreshAll()
        isRefreshing = false
        syncFromStore()
    }

    // MARK: Commands

    func setRoom(on: Bool) { run { try await self.service.setRoom(on: on) } }

    func apply(_ scene: LightScene) { run { try await self.service.apply(scene) } }

    func send(_ command: LightCommand, to bulb: BulbConfig) {
        if let current = states[bulb.id] { states[bulb.id] = current.applying(command) }
        run { try await self.service.send(command, to: bulb) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { /* error text is cached per bulb by LightService */ }
            syncFromStore()
        }
    }

    private func syncFromStore() {
        states = BulbStore.states
        errors = BulbStore.errors
        loginBlocked = BulbStore.credentialsRejected
        isConfigured = CredentialStore.load() != nil
    }

    // MARK: Settings

    func signIn(email: String, password: String) async throws -> String? {
        let warning = try await service.verifyAndSave(username: email, password: password)
        syncFromStore()
        await refresh()
        return warning
    }

    func signOut() {
        service.signOut()
        syncFromStore()
    }

    func saveBulbs(_ updated: [BulbConfig]) {
        BulbStore.bulbs = updated
        bulbs = updated
        service.resetSessions()
        Task { await refresh() }
    }

    var credentialLocation: String { CredentialStore.location.rawValue }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("TapoControl: launch at login change failed: \(error)")
            }
            objectWillChange.send()
        }
    }
}
