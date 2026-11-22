import SwiftUI
import SwiftData
import MapKit
import Charts
import HarkCore

struct LogView: View {
    @Query(sort: \Detection.firstHeard, order: .reverse) private var all: [Detection]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .timeline
    @State private var confirmedOnly = false
    @State private var search = ""
    @State private var group: ListenGroup?
    @State private var path = NavigationPath()
    @Environment(\.verticalSizeClass) private var verticalSize
    @Query(sort: \ListeningSession.started, order: .reverse) private var records: [ListeningSession]

    enum Mode: String, CaseIterable { case timeline = "Timeline", sessions = "Sessions", species = "Species", map = "Map" }

    private var isFiltered: Bool { group != nil || confirmedOnly }
    private func clearFilter() { group = nil; confirmedOnly = false }

    private var filterMenu: some View {
        Menu {
            Toggle(isOn: $confirmedOnly) { Label("Only ones I saw", systemImage: "eye") }
            Picker("Group", selection: $group) {
                Text("Everything").tag(ListenGroup?.none)
                ForEach(ListenGroup.allCases.filter { $0 != .sound }, id: \.self) { g in
                    Label { Text(g.title) } icon: { Image(symbol: g.symbol) }.tag(ListenGroup?.some(g))
                }
            }
            if isFiltered { Button("Show everything", role: .destructive) { clearFilter() } }
        } label: {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.title2).frame(width: 44, height: 36).contentShape(Rectangle())
        }
        .accessibilityLabel(isFiltered ? "Filter, on" : "Filter")
    }

    private var shown: [Detection] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return all.filter { d in
            (!confirmedOnly || d.confirmed)
            && (group == nil || ListenGroup(d.taxon) == group)
            && (q.isEmpty || d.common.localizedCaseInsensitiveContains(q) || d.scientific.localizedCaseInsensitiveContains(q)
                || (NameBook.shared.nickname(d.scientific)?.localizedCaseInsensitiveContains(q) ?? false))
        }
    }

    private var landscapeBar: Bool {
        if #available(iOS 26, *) { verticalSize == .compact } else { false }
    }

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .timeline: TimelineList(detections: shown, all: all, filtered: isFiltered, clear: clearFilter)
                case .sessions: SessionsList(detections: shown)
                case .species: SpeciesList(detections: shown, all: all)
                case .map: LogMap(detections: shown)
                }
            }
            // View switcher + filter at the bottom, where the thumb is.
            // Landscape (iOS 26): in the bottom toolbar, sharing one row with the minimized search button.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !landscapeBar {
                    HStack(spacing: 10) { modePicker; filterMenu }
                        .padding(.horizontal).padding(.vertical, 8)
                        .background(.bar)
                }
            }
            .toolbar {
                if landscapeBar {
                    ToolbarItem(placement: .bottomBar) { modePicker.frame(maxWidth: 420) }
                    ToolbarItem(placement: .bottomBar) { filterMenu }
                }
            }
            .modifier(SearchInBottomBar(on: landscapeBar))
            .navigationTitle("Log")
            .searchable(text: $search, prompt: "Search species")
            .modifier(MinimizedSearch(on: verticalSize == .compact))   // landscape: search shrinks to a button
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) { LogExportMenu(detections: shown) }
            }
            .navigationDestination(for: Detection.self) { DetectionDetail(detection: $0) }
            .navigationDestination(for: SessionSummary.self) { SessionPage(session: $0) }
            .onAppear {   // screenshot aid
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-opensession") {   // optional index: -opensession 2 = third most recent
                    let n = i + 1 < args.count ? Int(args[i + 1]) ?? 0 : 0
                    Task {   // after -demolog has seeded
                        try? await Task.sleep(for: .seconds(2))
                        let list = SessionSummary.build(all, records)
                        if list.indices.contains(n) { mode = .sessions; path.append(list[n]) }
                    }
                }
                #if DEBUG
                if args.contains("-sharecard"), let d = all.first(where: { $0.clipFile != nil }) { path.append(d) }
                if args.contains("-exportpdf"), let u = try? PDFExport(rows: all.map(ExportRow.init)).write() { NSLog("HARK pdf: %@", u.path) }
                #endif
                if let i = args.firstIndex(of: "-openspecies"), i + 1 < args.count {
                    mode = .species; path.append(SpeciesKey(scientific: args[i + 1]))
                }
            }
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
    WidgetBridge.refresh(ctx, listening: Listener.shared.state == .listening)
}

// MARK: Timeline

private struct TimelineList: View {
    let detections: [Detection]
    let all: [Detection]
    let filtered: Bool
    let clear: () -> Void
    @Environment(\.modelContext) private var ctx

    private var days: [(Date, [Detection])] {
        Dictionary(grouping: detections) { Calendar.current.startOfDay(for: $0.firstHeard) }.sorted { $0.key > $1.key }
    }

    var body: some View {
        List { Group {
            Section {
                if filtered {
                    Button { clear() } label: {
                        Label("Filtered: \(detections.count) of \(all.count). Show everything", systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.callout)
                    }
                }
                HStack {
                    stat("\(Set(all.map(\.scientific)).count)", "species heard")
                    Divider()
                    stat("\(Set(all.filter(\.confirmed).map(\.scientific)).count)", "confirmed")
                    Divider()
                    stat("\(all.count)", "detections")
                }
            }
            if detections.isEmpty {
                ContentUnavailableView(filtered ? "Nothing matches the filter" : "Nothing logged yet", systemImage: "mic",
                                       description: Text("Everything Hark identifies is saved here with time, place and a clip."))
            }
            ForEach(days, id: \.0) { day, items in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(items) { d in
                        NavigationLink(value: d) { LogRow(detection: d) }
                            .swipeActions(edge: .leading) {
                                Button { d.confirmed.toggle() } label: {
                                    Label(d.confirmed ? "Unconfirm" : "I saw it", systemImage: "eye")
                                }.tint(GoodStyle())
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleteDetection(d, in: ctx) } label: { Label("Delete", systemImage: "trash") }
                                Button { withAnimation { Listener.shared.notIt(d) } } label: { Label("Not it", systemImage: "xmark") }.tint(.orange)
                            }
                    }
                }
            }
        }.themedRows() }.themedList()
    }

    private func stat(_ n: String, _ label: String) -> some View {
        VStack { Text(n).font(.title2.bold().monospacedDigit()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity)
    }
}

struct LogRow: View {
    let detection: Detection
    private var subtitle: String {
        let time = detection.firstHeard.formatted(date: .omitted, time: .shortened)
        return "\(time) · \(detection.confidence.shownPercent)%" + (detection.source == "live" ? "" : " · by hand")
    }
    var body: some View {
        HStack(spacing: 12) {
            TaxonIcon(group: detection.taxon)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    SpeciesTitle(common: detection.common, scientific: detection.scientific, species: detection.isSpecies, style: .headline)
                    if detection.confirmed {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.good).font(.caption).accessibilityLabel("seen")
                    }
                    if detection.isFirst { NewBadge() }
                }
                SpeciesSubtitle(common: detection.common, scientific: detection.scientific, species: detection.isSpecies, row: true)
                Text(subtitle).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if detection.clipFile != nil { ClipButton(file: detection.clipFile, symbol: "") }
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
                    .font(.title2).foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .frame(width: 32)
        } else if !symbol.isEmpty {
            Image(symbol: symbol).frame(width: 32).foregroundStyle(.secondary)
        }
    }
}

// MARK: Species (life list)

private struct SpeciesList: View {
    let detections: [Detection]
    let all: [Detection]
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
        case .name:
            let b = NameBook.shared
            return r.sorted { b.plain($0.common, $0.scientific).localizedCaseInsensitiveCompare(b.plain($1.common, $1.scientific)) == .orderedAscending }
        }
    }

    /// Cumulative distinct species over time (whole log, not the current filter).
    private var growth: [(Date, Int)] {
        var seen = Set<String>(), out: [(Date, Int)] = []
        for d in all.sorted(by: { $0.firstHeard < $1.firstHeard }) where seen.insert(d.scientific).inserted {
            out.append((d.firstHeard, seen.count))
        }
        if let last = out.last { out.append((.now, last.1)) }
        return out
    }

    var body: some View {
        List { Group {
            Section {
                Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } footer: { Text("\(rows.count) species") }
            if growth.count > 1 {
                Section("Life list") {
                    Chart(growth, id: \.0) { p in
                        LineMark(x: .value("Date", p.0), y: .value("Species", p.1)).interpolationMethod(.stepEnd)
                        AreaMark(x: .value("Date", p.0), y: .value("Species", p.1)).interpolationMethod(.stepEnd)
                            .foregroundStyle(.tint.opacity(0.15))
                    }
                    .frame(height: 120)
                }
            }
            ForEach(rows) { r in
                NavigationLink(value: SpeciesKey(scientific: r.scientific)) {
                    HStack(spacing: 12) {
                        TaxonIcon(group: r.group)
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                SpeciesTitle(common: r.common, scientific: r.scientific, species: r.group.isSpecies, style: .headline)
                                if r.confirmed { Image(systemName: "checkmark.seal.fill").foregroundStyle(.good).font(.caption) }
                            }
                            Text("first \(r.first.formatted(date: .abbreviated, time: .omitted)) · last \(r.last.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(r.count)×").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }.themedRows() }.themedList()
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

    private var hours: [(Int, Int)] {
        let c = Dictionary(grouping: detections) { Calendar.current.component(.hour, from: $0.firstHeard) }.mapValues(\.count)
        return (0..<24).map { ($0, c[$0] ?? 0) }
    }
    private var months: [(Date, Int)] {
        Dictionary(grouping: detections) { Calendar.current.dateInterval(of: .month, for: $0.firstHeard)!.start }
            .map { ($0.key, $0.value.count) }.sorted { $0.0 < $1.0 }
    }

    private var best: Detection? { detections.filter { $0.clipFile != nil }.max { $0.confidence < $1.confidence } }

    var body: some View {
        List { Group {
            if let first = detections.last {
                Section {
                    HStack(spacing: 14) {
                        TaxonIcon(group: first.taxon, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            SpeciesTitle(common: first.common, scientific: scientific, species: first.isSpecies, style: .title2)
                            SpeciesSubtitle(common: first.common, scientific: scientific, species: first.isSpecies, font: .body)
                        }
                    }
                    LabeledContent("Times heard", value: "\(detections.count)")
                    LabeledContent("First heard", value: first.firstHeard.formatted(date: .abbreviated, time: .shortened))
                    if let last = detections.first { LabeledContent("Last heard", value: last.lastHeard.formatted(.relative(presentation: .named))) }
                    LabeledContent("Confirmed", value: detections.contains(where: \.confirmed) ? "Yes" : "Not yet")
                }
            }
            if let best, let file = best.clipFile {
                Section("Best recording") { ClipSpectrogram(file: file); HStack { ClipButton(file: file, symbol: "waveform"); Text("\(best.confidence.shownPercent)% · \(best.firstHeard.formatted(date: .abbreviated, time: .shortened))").font(.caption) } }
            }
            if detections.count >= 2 {
                Section("Time of day") {
                    Chart(hours, id: \.0) { h in
                        BarMark(x: .value("Hour", h.0), y: .value("Detections", h.1)).foregroundStyle(.tint)
                    }
                    .chartXScale(domain: 0...23)
                    .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                        AxisGridLine()
                        AxisValueLabel { if let h = v.as(Int.self) { Text(h == 0 ? "12a" : h == 12 ? "12p" : h < 12 ? "\(h)a" : "\(h - 12)p") } }
                    } }
                    .frame(height: 110)
                }
                if Set(detections.map { Calendar.current.component(.month, from: $0.firstHeard) }).count > 1 {
                    Section("Through the year") {
                        Chart(months, id: \.0) { m in
                            BarMark(x: .value("Month", m.0, unit: .month), y: .value("Detections", m.1)).foregroundStyle(.tint)
                        }
                        .frame(height: 110)
                    }
                }
            }
            let located = detections.filter { $0.latitude != nil }
            if !located.isEmpty {
                Section("Where") { DetectionMap(detections: located).frame(height: 200).listRowInsets(EdgeInsets()) }
            }
            Section("All detections") {
                ForEach(detections) { d in NavigationLink(value: d) { LogRow(detection: d) } }
            }
            if let first = detections.first, first.isSpecies {
                Section { NicknameRow(scientific: scientific) } header: { Text("Your name for it") } footer: {
                    Text("Shows instead of its name everywhere in Hark, like \"Fred\" for the cardinal at your feeder. Clear it to go back.")
                }
                LearnMoreSection(scientific: scientific, common: first.common, group: first.taxon)
            }
            Section {
                if listener.mutedNames.contains(scientific) {
                    Button("Show this species again") { listener.unmute(scientific) }
                } else if let i = listener.labels?.index(ofScientific: scientific) {
                    Button("Never show this species", role: .destructive) { listener.mute(i) }
                }
            }
        }.themedRows() }.themedList()
        .navigationTitle(detections.first?.displayName ?? scientific)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Detection detail

struct DetectionDetail: View {
    @Bindable var detection: Detection
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List { Group {
            Section {
                HStack(spacing: 14) {
                    TaxonIcon(group: detection.taxon, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { SpeciesTitle(common: detection.common, scientific: detection.scientific, species: detection.isSpecies, style: .title2); if detection.isFirst { NewBadge() } }
                        SpeciesSubtitle(common: detection.common, scientific: detection.scientific, species: detection.isSpecies, font: .body)
                    }
                }
                NavigationLink(value: SpeciesKey(scientific: detection.scientific)) { Text("All \(detection.displayName) detections") }
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
                LabeledContent("Best confidence", value: "\(detection.confidence.shownPercent)%")
                LabeledContent("How", value: ["live": "Live", "maybe": "Logged from a maybe", "unusual": "Logged though unusual here", "rewind": "Picked out on the spectrogram", "selection": "Picked out on the spectrogram"][detection.source] ?? detection.source)
            }
            if detection.latitude != nil {
                Section("Where") { DetectionMap(detections: [detection]).frame(height: 180).listRowInsets(EdgeInsets()) }
            }
            LearnMoreSection(scientific: detection.scientific, common: detection.common, group: detection.taxon)
            Section {
                Button("Not it: wrong ID", role: .destructive) { Listener.shared.notIt(detection); dismiss() }
                Button("Delete", role: .destructive) { deleteDetection(detection, in: ctx); dismiss() }
            } footer: { Text("Not it removes this and tells Hark it was wrong this time. To stop seeing a species altogether, long-press it on the Listen screen.") }
        }.themedRows() }.themedList()
        .toolbar { ToolbarItem(placement: .primaryAction) { DetectionShareButton(detection: detection) } }
        .navigationTitle(detection.displayName)
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
                Annotation(d.displayName, coordinate: CLLocationCoordinate2D(latitude: d.latitude!, longitude: d.longitude!)) {
                    Image(symbol: d.taxon.symbol).font(.caption).padding(5)
                        .background(d.confirmed ? AnyShapeStyle(.good) : AnyShapeStyle(.tint), in: Circle()).foregroundStyle(.white)
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

/// Landscape has little height to spare, so the bottom search field collapses to a button (iOS 26).
private struct MinimizedSearch: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.searchToolbarBehavior(on ? .minimize : .automatic) } else { content }
    }
}

private struct SearchInBottomBar: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26, *), on {
            content.toolbar {
                ToolbarSpacer(.fixed, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        } else { content }
    }
}
