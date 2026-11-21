import SwiftUI
import HarkCore

/// Results of "What was that?": the best IDs over the last 15 seconds, each loggable, optionally as confirmed.
struct CaptureSheet: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    let result: CaptureResult
    @State private var done: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if result.hits.isEmpty {
                    ContentUnavailableView("Nothing clear", systemImage: "ear.trianglebadge.exclamationmark",
                                           description: Text("Nothing scored above \(Int(min(listener.threshold, 0.15) * 100))% in the last 15 seconds."))
                }
                ForEach(result.hits, id: \.label.scientific) { hit in
                    VStack(alignment: .leading, spacing: 8) {
                        NowRow(label: hit.label, confidence: hit.confidence)
                        if hit.label.group.isSpecies {
                            if done.contains(hit.label.scientific) {
                                Label("Logged", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                            } else {
                                HStack {
                                    Button("Log it") { log(hit, confirmed: false) }.buttonStyle(.bordered)
                                    Button { log(hit, confirmed: true) } label: { Label("I saw it", systemImage: "eye") }
                                        .buttonStyle(.borderedProminent)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Last 15 seconds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func log(_ hit: (label: HarkCore.Label, confidence: Float), confirmed: Bool) {
        listener.logFromCapture(hit.label, confidence: hit.confidence, confirmed: confirmed)
        done.insert(hit.label.scientific)
    }
}
