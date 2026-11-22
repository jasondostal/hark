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
                if ProcessInfo.processInfo.arguments.contains("-select") {   // screenshot aid: freeze, select 1.5 s, identify
                    try? await Task.sleep(for: .seconds(9)); listener.freezeForSelection()
                    let s = listener.selection; s.select(max(s.viewEnd - 112_000, 0), max(s.viewEnd - 64_000, 0)); await s.analyze(listener)   // 1.5 s
                }
            }
        }
        .modelContainer(for: [Detection.self, ListeningSession.self])
    }
}
