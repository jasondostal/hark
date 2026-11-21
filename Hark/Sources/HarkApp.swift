import SwiftUI
import SwiftData

@main
struct HarkApp: App {
    @State private var listener = Listener.shared
    init() { SelfTest.runIfRequested() }
    var body: some Scene {
        WindowGroup {
            ListenView()
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
