import SwiftUI
import SwiftData
import MapKit
import HarkCore

struct LogView: View {
    @Query(sort: \Detection.firstHeard, order: .reverse) private var all: [Detection]
    @Environment(\.modelContext) private var ctx
    @State private var mode: Mode = .timeline
    @State private var confirmedOnly = false

    enum Mode: String, CaseIterable { case timeline = "Timeline", species = "Species", map = "Map" }

    private var shown: [Detection] { confirmedOnly ? all.filter(\.confirmed) : all }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 6)
                switch mode {
                case .timeline: TimelineList(detections: shown, all: all, confirmedOnly: $confirmedOnly)
                case .species: SpeciesList(detections: shown, confirmedOnly: $confirmedOnly)
                case .map: LogMap(detections: shown)
                }
            }
            .navigationTitle("Log")
            .navigationDestination(for: Detection.self) { DetectionDetail(detection: $0) }
            .navigationDestination(for: SpeciesKey.self) { SpeciesPage(scientific: $0.scientific) }
        }
    }
}

struct SpeciesKey: Hashable { let scientific: String }

/// Delete a detection and its clip.
@MainActor func deleteDetection(_ d: Detection, in ctx: ModelContext) {
    if ClipPlayer.shared.playingID == d.clipFile { ClipPlayer.shared.stop() }
    ClipStore.delete(d.clipFile)
    ctx.delete(d)
}

// MARK: Timeline

private struct TimelineList: View {
    let detections: [Detection]
    let all: [Detection]
    @Binding var confirmedOnly: Bool
    @Environment(\.modelContext) private var ctx

    private var days: [(Date, [Detection])] {
        Dictionary(grouping: detections) { Calendar.current.startOfDay(for: $0.firstHeard) }.sorted { $0.key > $1.key }
    }

    var body: some View {
        List {
            Section {
                Toggle("Only ones I saw", isOn: $confirmedOnly)
                HStack {
                    stat("\(Set(all.map(\.scientific)).count)", "species heard")
                    Divider()
                    stat("\(Set(all.filter(\.confirmed).map(\.scientific)).count)", "confirmed")
                    Divider()
                    stat("\(all.count)", "detections")
                }
            }
            if detections.isEmpty {
                ContentUnavailableView(confirmedOnly ? "Nothing confirmed yet" : "Nothing logged yet", systemImage: "ear",
                                       description: Text("Everything Hark identifies is saved here with time, place and a clip."))
            }
            ForEach(days, id: \.0) { day, items in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(items) { d in
                        NavigationLink(value: d) { LogRow(detection: d) }
                            .swipeActions(edge: .leading) {
                                Button { d.confirmed.toggle() } label: {
                                    Label(d.confirmed ? "Unconfirm" : "I saw it", systemImage: "eye")
                                }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleteDetection(d, in: ctx) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
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
            ClipButton(file: detection.clipFile, symbol: detection.taxon.symbol)
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(detection.common).font(.headline)
                    if detection.confirmed { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption) }
                    if detection.isFirst { NewBadge() }
                }
                Text(detection.scientific).font(.caption).italic().foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(detection.firstHeard.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit())
                Text("\(Int(detection.confidence * 100))%\(detection.source == "live" ? "" : " · \(detection.source)")")
                    .font(.caption2).foregroundStyle(.secondary)
                if detection.latitude != nil { Image(systemName: "location.fill").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
    }
}

struct NewBadge: View {
    var body: some View {
        Text("NEW").font(.caption2.weight(.heavy)).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1).background(.orange, in: Capsule())
    }
}

/// Play/stop a saved clip; shows the group symbol when there's no clip.
struct ClipButton: View {
    let file: String?
    let symbol: String
    private var player: ClipPlayer { ClipPlayer.shared }
    var body: some View {
        if let file {
            Button {
                player.toggle(id: file, samples: nil, file: ClipStore.url(file))
            } label: {
                Image(systemName: player.playingID == file ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .frame(width: 32)
        } else {
            Image(systemName: symbol).frame(width: 32).foregroundStyle(.secondary)
        }
    }
}

// MARK: Species (life list)

private struct SpeciesList: View {
    let detections: [Detection]
    @Binding var confirmedOnly: Bool
    @State private var sort: Sort = .recent
    enum Sort: String, CaseIterable { case recent = "Recent", count = "Most heard", name = "A–Z" }

    private struct Row: Identifiable {
        let scientific: String, common: String, group: TaxonGroup
        let count: Int, first: Date, last: Date, confirmed: Bool
        var id: String { scientific }
    }

    private var rows: [Row] {
        let r = Dictionary(grouping: detections, by: \.scientific).map { s, ds in
            Row(scientific: s, common: ds[0].common, group: ds[0].taxon, count: ds.count,
                first: ds.map(\.firstHeard).min()!, last: ds.map(\.lastHeard).max()!, confirmed: ds.contains(where: \.confirmed))
        }
        switch sort {
        case .recent: return r.sorted { $0.last > $1.last }
        case .count: return r.sorted { ($0.count, $0.last) > ($1.count, $1.last) }
        case .name: return r.sorted { $0.common.localizedCaseInsensitiveCompare($1.common) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Only ones I saw", isOn: $confirmedOnly)
                Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } footer: { Text("\(rows.count) species") }
            ForEach(rows) { r in
                NavigationLink(value: SpeciesKey(scientific: r.scientific)) {
                    HStack {
                        Image(systemName: r.group.symbol).frame(width: 28).foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text(r.common).font(.headline)
                                if r.confirmed { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption) }
                            }
                            Text("first \(r.first.formatted(date: .abbreviated, time: .omitted)) · last \(r.last.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(r.count)×").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct SpeciesPage: View {
    let scientific: String
    @Query private var detections: [Detection]
    @Environment(Listener.self) private var listener

    init(scientific: String) {
        self.scientific = scientific
        _detections = Query(filter: #Predicate<Detection> { $0.scientific == scientific }, sort: \.firstHeard, order: .reverse)
    }

    private var best: Detection? { detections.filter { $0.clipFile != nil }.max { $0.confidence < $1.confidence } }

    var body: some View {
        List {
            if let first = detections.last {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(first.taxon.rawValue.capitalized, systemImage: first.taxon.symbol).font(.caption).foregroundStyle(.secondary)
                        Text(first.common).font(.title.bold())
                        Text(scientific).italic().foregroundStyle(.secondary)
                    }
                    LabeledContent("Times heard", value: "\(detections.count)")
                    LabeledContent("First heard", value: first.firstHeard.formatted(date: .abbreviated, time: .shortened))
                    if let last = detections.first { LabeledContent("Last heard", value: last.lastHeard.formatted(.relative(presentation: .named))) }
                    LabeledContent("Confirmed", value: detections.contains(where: \.confirmed) ? "Yes" : "Not yet")
                }
            }
            if let best, let file = best.clipFile {
                Section("Best recording") { ClipSpectrogram(file: file); HStack { ClipButton(file: file, symbol: "waveform"); Text("\(Int(best.confidence * 100))% · \(best.firstHeard.formatted(date: .abbreviated, time: .shortened))").font(.caption) } }
            }
            let located = detections.filter { $0.latitude != nil }
            if !located.isEmpty {
                Section("Where") { DetectionMap(detections: located).frame(height: 200).listRowInsets(EdgeInsets()) }
            }
            Section("All detections") {
                ForEach(detections) { d in NavigationLink(value: d) { LogRow(detection: d) } }
            }
            Section {
                if let url = URL(string: "https://www.inaturalist.org/search?q=" + (scientific.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                    Link(destination: url) { Label("Look it up on iNaturalist", systemImage: "safari") }
                }
                if listener.mutedNames.contains(scientific) {
                    Button("Show this species again") { listener.unmute(scientific) }
                } else if let i = listener.labels?.index(ofScientific: scientific) {
                    Button("Never show this species", role: .destructive) { listener.mute(i) }
                }
            }
        }
        .navigationTitle(detections.first?.common ?? scientific)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Detection detail

struct DetectionDetail: View {
    @Bindable var detection: Detection
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(detection.common).font(.title2.bold()); if detection.isFirst { NewBadge() } }
                    Text(detection.scientific).italic().foregroundStyle(.secondary)
                }
                NavigationLink(value: SpeciesKey(scientific: detection.scientific)) { Text("All \(detection.common) detections") }
            }
            if let file = detection.clipFile {
                Section("Recording") {
                    ClipSpectrogram(file: file)
                    HStack { ClipButton(file: file, symbol: "waveform"); Text("Play the clip").font(.callout) }
                }
            }
            Section {
                Toggle(isOn: $detection.confirmed) { Label("I saw it", systemImage: "eye") }
                LabeledContent("Heard", value: detection.firstHeard.formatted(date: .abbreviated, time: .standard))
                if detection.lastHeard.timeIntervalSince(detection.firstHeard) > 1 {
                    LabeledContent("Until", value: detection.lastHeard.formatted(date: .omitted, time: .standard))
                }
                LabeledContent("Best confidence", value: "\(Int(detection.confidence * 100))%")
                LabeledContent("Windows", value: "\(detection.windows)")
                LabeledContent("How", value: ["live": "Live", "maybe": "Logged from a maybe", "unusual": "Logged though unusual here", "rewind": "Picked out in Rewind"][detection.source] ?? detection.source)
            }
            if detection.latitude != nil {
                Section("Where") { DetectionMap(detections: [detection]).frame(height: 180).listRowInsets(EdgeInsets()) }
            }
            Section {
                Button("Delete", role: .destructive) { deleteDetection(detection, in: ctx); dismiss() }
            }
        }
        .navigationTitle(detection.common)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Spectrogram of a saved clip, computed on first display.
struct ClipSpectrogram: View {
    let file: String
    @State private var image: CGImage?
    var body: some View {
        ZStack {
            Color.black
            if let image { Image(decorative: image, scale: 1).resizable().interpolation(.medium) } else { ProgressView().tint(.white) }
        }
        .frame(height: 140)
        .listRowInsets(EdgeInsets())
        .task(id: file) {
            let f = file
            image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let s = ClipStore.load(f) else { return nil }
                let lv = SpectrogramDSP.levels(of: s)
                return SpectrogramDSP.image(lv.data, columns: lv.columns)
            }.value
        }
    }
}

// MARK: Map

struct DetectionMap: View {
    let detections: [Detection]
    var body: some View {
        Map {
            ForEach(detections.filter { $0.latitude != nil }) { d in
                Annotation(d.common, coordinate: CLLocationCoordinate2D(latitude: d.latitude!, longitude: d.longitude!)) {
                    Image(systemName: d.taxon.symbol).font(.caption).padding(5)
                        .background(d.confirmed ? Color.green : Color.accentColor, in: Circle()).foregroundStyle(.white)
                }
            }
        }
    }
}

private struct LogMap: View {
    let detections: [Detection]
    @State private var range: Range = .week
    enum Range: String, CaseIterable { case today = "Today", week = "7 days", all = "All" }

    private var filtered: [Detection] {
        let cut: Date? = switch range {
        case .today: Calendar.current.startOfDay(for: .now)
        case .week: Date.now.addingTimeInterval(-7 * 86_400)
        case .all: nil
        }
        return detections.filter { $0.latitude != nil && (cut == nil || $0.firstHeard >= cut!) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DetectionMap(detections: filtered)
            Picker("Range", selection: $range) { ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding()
            if filtered.isEmpty {
                ContentUnavailableView("No located detections", systemImage: "map",
                                       description: Text("Detections are placed on the map when location access is on."))
                    .padding(.top, 80)
            }
        }
    }
}
