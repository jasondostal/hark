import WidgetKit
import SwiftUI
import AppIntents

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snap: WidgetSnapshot(lifeCount: 42, todayCount: 3, today: [
            .init(name: "Black-capped Chickadee", symbol: "bird.fill", time: .now, isFirst: false),
            .init(name: "Blue Jay", symbol: "bird.fill", time: .now, isFirst: false),
            .init(name: "Spring Peeper", symbol: "frog.fill", time: .now, isFirst: true)], updated: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SnapshotEntry(date: .now, snap: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // the app reloads us whenever it logs; also roll over at midnight so "today" resets
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [SnapshotEntry(date: .now, snap: .load())], policy: .after(midnight)))
    }
}

/// Home Screen + Lock Screen: today's species and a one-tap Listen button.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.ducktyping.hark.today", provider: SnapshotProvider()) { e in
            TodayWidgetView(entry: e).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hark")
        .description("Today's species, and one tap to start listening.")
        .supportedFamilies(WidgetSnapshot.available
            ? [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
            : [.systemSmall, .accessoryCircular])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry
    private var s: WidgetSnapshot { entry.snap }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Button(intent: StartListeningIntent()) {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "mic.fill").font(.title3)
                        if WidgetSnapshot.available { Text("\(s.todayCount)").font(.caption.bold().monospacedDigit()) }
                    }
                }
            }.buttonStyle(.plain)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Hark · \(s.todayCount) today", systemImage: "mic.fill").font(.headline).widgetAccentable()
                if let last = s.today.first {
                    Text(last.name).font(.caption).lineLimit(1)
                    Text(last.time, style: .relative).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Tap to listen").font(.caption)
                }
            }
            .widgetURL(URL(string: "hark://listen"))
        case .accessoryInline:
            Label("\(s.todayCount) species today", systemImage: "mic.fill")
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                listenButton.frame(width: 104)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if s.today.isEmpty { Text("Nothing heard yet").font(.callout).foregroundStyle(.secondary) }
                    ForEach(s.today.prefix(4), id: \.self) { i in
                        HStack(spacing: 6) {
                            Image(symbol: i.symbol).font(.caption).foregroundStyle(.secondary).frame(width: 16)
                            Text(i.name).font(.callout).lineLimit(1)
                            if i.isFirst { Text("NEW").font(.system(size: 9, weight: .heavy)).foregroundStyle(.orange) }
                            Spacer(minLength: 0)
                            Text(i.time, format: .dateTime.hour().minute()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        default:
            listenButton
        }
    }

    private var listenButton: some View {
        VStack(spacing: 6) {
            Button(intent: StartListeningIntent()) {
                Image(systemName: "mic.fill").font(.system(size: 30, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.green)
            if !WidgetSnapshot.available {
                Text("Listen").font(.headline)
            } else {
            HStack(spacing: 4) {
                Text("\(s.todayCount)").font(.headline.monospacedDigit())
                Text("today").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text("\(s.lifeCount)").font(.headline.monospacedDigit())
                Text("life").font(.caption).foregroundStyle(.secondary)
            }
            }
        }
    }
}
