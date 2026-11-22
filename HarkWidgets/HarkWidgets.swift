import WidgetKit
import SwiftUI
import AppIntents

@main
struct HarkWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ListenControl()
        ListeningLiveActivity()
    }
}

/// Control Center / Lock Screen / Action Button control: one tap opens Hark listening.
struct ListenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.ducktyping.hark.listen") {
            ControlWidgetButton(action: StartListeningIntent()) {
                Label("Hark", systemImage: "mic.fill")
            }
        }
        .displayName("Start Listening")
        .description("Open Hark and start identifying what you hear.")
    }
}

struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningAttributes.self) { ctx in
            HStack(spacing: 12) {
                Image(systemName: "mic.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Hark is listening").font(.headline)
                        Text(ctx.attributes.started, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let latest = ctx.state.latest {
                        Label { Text(ctx.state.latestIsFirst ? "New for you: \(latest)" : latest) }
                              icon: { Image(symbol: ctx.state.latestSymbol ?? "bird.fill") }
                            .font(.subheadline).foregroundStyle(ctx.state.latestIsFirst ? .orange : .primary)
                    } else {
                        Text("Nothing yet").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack {
                    Text("\(ctx.state.species)").font(.title2.bold().monospacedDigit())
                    Text("species").font(.caption2).foregroundStyle(.secondary)
                }
                Button(intent: StopListeningIntent()) { Image(systemName: "stop.fill") }
                    .tint(.red)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(ctx.state.species) species", systemImage: "mic.fill").font(.caption).foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopListeningIntent()) { Image(systemName: "stop.fill") }.tint(.red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let latest = ctx.state.latest {
                        Label { Text(ctx.state.latestIsFirst ? "New for you: \(latest)" : latest) } icon: { Image(symbol: ctx.state.latestSymbol ?? "bird.fill") }
                    } else {
                        Text("Listening…").foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "mic.fill").foregroundStyle(.green)
            } compactTrailing: {
                Text("\(ctx.state.species)").monospacedDigit()
            } minimal: {
                Image(systemName: "mic.fill").foregroundStyle(.green)
            }
        }
    }
}
