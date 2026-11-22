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
                if ProcessInfo.processInfo.arguments.contains("-select") {   // screenshot aid: freeze, grab 5 s, identify
                    try? await Task.sleep(for: .seconds(9)); listener.freezeForSelection()
                    let s = listener.selection; s.grab(around: max(s.viewEnd - 3 * 32_000, 0)); await s.analyze(listener)
                }
            }
        }
        .modelContainer(for: [Detection.self, ListeningSession.self])
    }
}
