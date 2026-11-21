import SwiftUI
import SwiftData

@main
struct HarkApp: App {
    @State private var listener = Listener.shared
    init() { SelfTest.runIfRequested() }
    var body: some Scene {
        WindowGroup {
            TabView {
                ListenView().tabItem { Label("Listen", systemImage: "ear") }
                LogView().tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            }
            .environment(listener)
            .task {
                await listener.loadModel()
                // Testing aid: start listening right away (simulator / devicectl launches).
                if ProcessInfo.processInfo.arguments.contains("-autolisten") { await listener.start() }
                if ProcessInfo.processInfo.arguments.contains("-rewind") {   // screenshot aid
                    try? await Task.sleep(for: .seconds(9)); listener.openRewind()
                }
            }
        }
        .modelContainer(for: Detection.self)
    }
}
