import SwiftUI
import UIKit
import SwiftData

@main
struct HarkApp: App {
    @State private var listener = Listener.shared
    init() {
        SelfTest.runIfRequested(); HarkTips.configure()
        // Navigation titles take the look's face from the first bar on (themeRoot keeps it current after that).
        let palette = SpectrogramPalette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "") ?? .aurora
        AppTheme.stored.applyAppearance(ink: AppTheme.stored.surface(palette).ink)
    }
    var body: some Scene {
        WindowGroup {
            ListenView()
            .environment(listener)
            .themeRoot()
            .onOpenURL { url in
                if url.isFileURL { FileAnalysis.shared.receive(url) }      // "Open in Hark" from Files, AirDrop, a share sheet
                else if url.host == "listen" { Task { await listener.requestStart() } }
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-landscape"),     // screenshot aid
                   let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                }
                #endif
                await listener.loadModel()
                // Testing aid: start listening right away (simulator / devicectl launches).
                if ProcessInfo.processInfo.arguments.contains("-autolisten") { await listener.start() }
                let args = ProcessInfo.processInfo.arguments   // testing aid: -analyzefile a.wav,b.wav (add -files to watch)
                if let i = args.firstIndex(of: "-analyzefile"), i + 1 < args.count {
                    try? await Task.sleep(for: .seconds(1))    // ListenView hands over the model context on appear
                    FileAnalysis.shared.add(args[i + 1].split(separator: ",").map { URL(fileURLWithPath: String($0)) })
                    FileAnalysis.shared.start(listener)
                }
                if ProcessInfo.processInfo.arguments.contains("-select") {   // screenshot aid: freeze, select 1.5 s, identify
                    try? await Task.sleep(for: .seconds(9)); listener.freezeForSelection()
                    let s = listener.selection; s.select(max(s.viewEnd - 112_000, 0), max(s.viewEnd - 64_000, 0)); await s.analyze(listener)   // 1.5 s
                }
            }
        }
        .modelContainer(for: [Detection.self, ListeningSession.self])
    }
}
