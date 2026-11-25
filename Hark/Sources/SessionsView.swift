import SwiftUI
import SwiftData
import MapKit
import Charts
import HarkCore

/// A listening session as the log sees it: its record (if any; older sessions predate records) plus detections.
struct SessionSummary: Identifiable, Hashable {
    let id: UUID
    let start: Date
    let end: Date
    let detections: [Detection]
    let record: ListeningSession?
    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
    var species: [String] {   // most-heard first
        Dictionary(grouping: detections, by: \.displayName).sorted { ($0.value.count, $0.key) > ($1.value.count, $1.key) }.map(\.key)
    }
    var kind: String { record?.kind ?? "live" }
    /// Your name for it, or what it was: "Point count", "Survey", a recording's file name.
    var name: String? {
        if let t = record?.title, !t.isEmpty { return t }
        switch kind { case "point": return "Point count"; case "survey": return "Survey"; case "file": return "Recording"; default: return nil }
    }
    var symbol: String {
        switch kind { case "point": "mappin.and.ellipse"; case "survey": "figure.walk"; case "file": "waveform"; default: "dot.radiowaves.left.and.right" }
    }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static func build(_ detections: [Detection], _ records: [ListeningSession]) -> [SessionSummary] {
        let byID = Dictionary(grouping: detections, by: \.sessionID)
        let recs = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Set(byID.keys).union(recs.keys).compactMap { id in
            let ds = (byID[id] ?? []).sorted { $0.firstHeard < $1.firstHeard }
            let r = recs[id]
            let start = r?.started ?? ds.first?.firstHeard
            let end = r?.ended ?? ds.map(\.lastHeard).max()
            guard let start, let end else { return nil }
            if ds.isEmpty && end.timeIntervalSince(start) < 60 && (r?.kind ?? "live") == "live" { return nil }   // a quick tap that heard nothing
            return SessionSummary(id: id, start: start, end: max(end, ds.map(\.lastHeard).max() ?? end), detections: ds, record: r)
        }
        .sorted { $0.start > $1.start }
    }
}

struct SessionsList: View {
    let detections: [Detection]
    @Query(sort: \ListeningSession.started, order: .reverse) private var records: [ListeningSession]

    var body: some View {
        let sessions = SessionSummary.build(detections, records)
        List { Group {
            if sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "figure.walk",
                                       description: Text("Each time you listen becomes a session with its route and what you heard."))
            }
            ForEach(sessions) { s in
                NavigationLink(value: s) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(s.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Spacer()
                            Text(Self.duration(s.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if let n = s.name {
                            Label(n, systemImage: s.symbol).font(.caption.weight(.semibold)).foregroundStyle(.tint).lineLimit(1)
                        }
                        Text("\(Set(s.detections.map(\.scientific)).count) species · \(s.detections.count) detections")
                            .font(.caption).foregroundStyle(.secondary)
                        if !s.species.isEmpty {
                            Text(s.species.prefix(4).joined(separator: ", ") + (s.species.count > 4 ? "…" : ""))
                                .font(.caption).lineLimit(1)
                        }
                    }
                }
            }
        }.themedRows() }.themedList()
    }

    /// m:ss into a session.
    static func clock(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m < 1 ? "<1 min" : m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }
}

struct SessionPage: View {
    let session: SessionSummary
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    /// The tally: each species once, with when it was first heard (time into the session) and how often.
    private struct Tally: Identifiable { let id: String; let first: Detection; let count: Int; let best: Double; let offset: TimeInterval }
    private var tally: [Tally] {
        Dictionary(grouping: session.detections, by: \.scientific).map { s, ds in
            let first = ds.min { $0.firstHeard < $1.firstHeard }!
            return Tally(id: s, first: first, count: ds.reduce(0) { $0 + max($1.windows, 1) }, best: ds.map(\.confidence).max() ?? 0,
                         offset: max(first.firstHeard.timeIntervalSince(session.start), 0))
        }
        .sorted { $0.offset < $1.offset }
    }

    private struct Span: Identifiable { let id = UUID(); let name: String; let start: Date; let end: Date; let confirmed: Bool; var labeled = false }

    private var spans: [Span] {
        let minWidth = max(session.duration * 0.012, 4)
        var named = Set<String>()
        return session.detections.map {   // detections are sorted by time; label each species' first bar
            Span(name: $0.displayName, start: $0.firstHeard,
                 end: max($0.lastHeard.addingTimeInterval(5), $0.firstHeard.addingTimeInterval(minWidth)),
                 confirmed: $0.confirmed, labeled: named.insert($0.common).inserted)
        }
    }

    var body: some View {
        List { Group {
            Section {
                if let r = session.record {
                    @Bindable var r = r
                    LabeledContent("Name") {
                        TextField(session.name ?? "Add a name", text: $r.title).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Kind", value: kindTitle)
                } else if let n = session.name { Text(n).font(.headline) }
                LabeledContent("Length", value: SessionsList.duration(session.duration))
                LabeledContent("Species", value: "\(Set(session.detections.map(\.scientific)).count)")
                if let r = session.record, r.trackLat.count > 1 {
                    LabeledContent("Distance", value: Measurement(value: distance(r), unit: UnitLength.meters)
                        .formatted(.measurement(width: .abbreviated, usage: .road)))
                }
            }
            if let r = session.record {
                @Bindable var r = r
                Section("Notes") {
                    TextField("Weather, habitat, who you were with…", text: $r.note, axis: .vertical).lineLimit(1...6)
                }
            }
            if session.kind != "live", !tally.isEmpty {
                Section {
                    ForEach(tally) { t in
                        NavigationLink(value: t.first) {
                            HStack(spacing: 10) {
                                TaxonIcon(group: t.first.taxon, size: 28)
                                Text(t.first.displayName).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(SessionsList.clock(t.offset)) · \(t.best.shownPercent)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Tally") } footer: {
                    Text("Each species once, in the order it was first heard, with the time into the \(session.kind == "file" ? "recording" : "session").")
                }
            }
            if hasMap {
                Section(session.kind == "point" ? "Where" : "Route") { routeMap.frame(height: 240).listRowInsets(EdgeInsets()) }
            }
            if !spans.isEmpty {
                Section("When each was heard") {
                    let names = session.species
                    Chart(spans) { s in
                        BarMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end), y: .value("Species", s.name), height: 8)
                            .foregroundStyle(s.confirmed ? AnyShapeStyle(.good) : AnyShapeStyle(.tint))
                            .cornerRadius(2)
                            .annotation(position: .top, alignment: .leading, spacing: 2,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                if s.labeled { Text(s.name).font(.caption2).foregroundStyle(.secondary).fixedSize() }
                            }
                    }
                    .chartYScale(domain: names)
                    .chartYAxis(.hidden)
                    .chartXScale(domain: session.start...max(session.end, session.start.addingTimeInterval(60)))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisGridLine(); AxisValueLabel(format: session.duration < 600 ? .dateTime.hour().minute().second() : .dateTime.hour().minute()) } }
                    .frame(height: CGFloat(max(names.count, 2)) * 30 + 30)
                    .padding(.vertical, 6)
                }
            }
            Section("Detections") {
                ForEach(session.detections.reversed()) { d in NavigationLink(value: d) { LogRow(detection: d) } }
            }
            Section {
                Button("Delete this session", role: .destructive) { delete() }
            }
        }.themedRows() }.themedList()
        .toolbar { ToolbarItem(placement: .primaryAction) { LogExportMenu(detections: session.detections, raven: (session.start, session.name ?? session.start.formatted(.iso8601.year().month().day()))) } }
        .onDisappear { try? ctx.save() }      // name and notes
        .navigationTitle(session.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasMap: Bool {
        (session.record?.trackLat.count ?? 0) > 1 || session.detections.contains { $0.latitude != nil } || session.record?.latitude != nil
    }

    private var kindTitle: String {
        switch session.kind {
        case "point": (session.record?.plannedSeconds ?? 0) > 0 ? "Point count, \((session.record?.plannedSeconds ?? 0) / 60) min" : "Point count"
        case "survey": "Survey"
        case "file": "Recording"
        default: "Live"
        }
    }

    private func delete() {
        // Like deleting one detection: gone now, with Undo for a few seconds (the clips are kept until then).
        let ctx = ctx
        let (snaps, commit) = removeDetections(session.detections, in: ctx)
        var remake: (() -> ListeningSession)?
        if let r = session.record {
            let (id, started, ended, lat, lon) = (r.id, r.started, r.ended, r.trackLat, r.trackLon)
            let (kind, planned, title, note, la, lo) = (r.kind, r.plannedSeconds, r.title, r.note, r.latitude, r.longitude)
            remake = {
                let n = ListeningSession(id: id, started: started)
                n.ended = ended; n.trackLat = lat; n.trackLon = lon; n.kind = kind; n.plannedSeconds = planned
                n.title = title; n.note = note; n.latitude = la; n.longitude = lo
                return n
            }
            ctx.delete(r)
        }
        try? ctx.save()
        UndoCenter.shared.offer("Deleted session (\(snaps.count) detections)", undo: {
            snaps.forEach { _ = $0.restore(in: ctx) }
            if let remake { ctx.insert(remake()) }
            try? ctx.save()
            WidgetBridge.refresh(ctx, listening: Listener.shared.state == .listening)
        }, commit: commit)
        dismiss()
    }

    private var routeMap: some View {
        Map {
            if let r = session.record, r.trackLat.count > 1 {
                MapPolyline(coordinates: zip(r.trackLat, r.trackLon).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) })
                    .stroke(.blue, lineWidth: 4)
            }
            if let r = session.record, session.kind == "point", let lat = r.latitude, let lon = r.longitude {
                Annotation("Station", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                    Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(.red, .white)
                }
            }
            ForEach(session.kind == "point" ? [] : session.detections.filter { $0.latitude != nil }) { d in
                Annotation(d.displayName, coordinate: CLLocationCoordinate2D(latitude: d.latitude!, longitude: d.longitude!)) {
                    DetectionPin(detection: d, small: true)
                }
            }
        }
    }

    private func distance(_ r: ListeningSession) -> Double {
        let pts = zip(r.trackLat, r.trackLon).map { CLLocation(latitude: $0, longitude: $1) }
        return zip(pts, pts.dropFirst()).reduce(0) { $0 + $1.0.distance(from: $1.1) }
    }
}
