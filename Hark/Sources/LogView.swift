import SwiftUI
import SwiftData
import HarkCore

struct LogView: View {
    @Query(sort: \Detection.firstHeard, order: .reverse) private var all: [Detection]
    @Environment(\.modelContext) private var ctx
    @State private var confirmedOnly = false

    private var shown: [Detection] { confirmedOnly ? all.filter(\.confirmed) : all }
    private var days: [(Date, [Detection])] {
        Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.firstHeard) }
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $confirmedOnly) {
                        Text("All").tag(false); Text("I saw it").tag(true)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        stat("\(Set(all.map(\.scientific)).count)", "species heard")
                        Divider()
                        stat("\(Set(all.filter(\.confirmed).map(\.scientific)).count)", "confirmed")
                    }
                }
                if shown.isEmpty {
                    ContentUnavailableView(confirmedOnly ? "Nothing confirmed yet" : "Nothing logged yet",
                                           systemImage: "ear",
                                           description: Text("Everything Hark identifies is saved here with time and place."))
                }
                ForEach(days, id: \.0) { day, items in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(items) { d in
                            LogRow(detection: d)
                                .swipeActions(edge: .leading) {
                                    Button { d.confirmed.toggle() } label: {
                                        Label(d.confirmed ? "Unconfirm" : "I saw it", systemImage: "eye")
                                    }.tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { ctx.delete(d) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Log")
        }
    }

    private func stat(_ n: String, _ label: String) -> some View {
        VStack { Text(n).font(.title2.bold().monospacedDigit()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity)
    }
}

struct LogRow: View {
    let detection: Detection
    var body: some View {
        HStack {
            Image(systemName: detection.taxon.symbol).frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(detection.common).font(.headline)
                    if detection.confirmed { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption) }
                }
                Text(detection.scientific).font(.caption).italic().foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(detection.firstHeard.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit())
                Text("\(Int(detection.confidence * 100))%\(detection.source == "maybe" ? " · maybe" : "")")
                    .font(.caption2).foregroundStyle(.secondary)
                if detection.latitude != nil { Image(systemName: "location.fill").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
    }
}
