import SwiftUI
import SwiftData

@main
struct HarkApp: App {
    @State private var listener = Listener.shared
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-logtab") ? 1 : 0   // screenshot aid
    init() { SelfTest.runIfRequested() }
    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                ListenView().tabItem { Label("Listen", systemImage: "ear") }.tag(0)
                LogView().tabItem { Label("Log", systemImage: "list.bullet.rectangle") }.tag(1)
            }
            .environment(listener)
            .onOpenURL { url in
                if url.host == "listen" { Task { await listener.requestStart() } }
            }
            .task {
                await listener.loadModel()
                // Testing aid: start listening right away (simulator / devicectl launches).
                if ProcessInfo.processInfo.arguments.contains("-autolisten") { await listener.start() }
                if ProcessInfo.processInfo.arguments.contains("-rewind") {   // screenshot aid
                    try? await Task.sleep(for: .seconds(9)); listener.openRewind()
                }
            }
        }
        .modelContainer(for: [Detection.self, ListeningSession.self])
    }
}
