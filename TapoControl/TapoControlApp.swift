import SwiftUI

@main
struct TapoControlApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.roomIsOn ? "lightbulb.2.fill" : "lightbulb.2")
        }
        .menuBarExtraStyle(.window)
    }
}
