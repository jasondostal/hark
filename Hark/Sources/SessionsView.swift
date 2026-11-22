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
        Dictionary(grouping: detections, by: \.common).sorted { ($0.value.count, $0.key) > ($1.value.count, $1.key) }.map(\.key)
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
            if ds.isEmpty && end.timeIntervalSince(start) < 60 { return nil }   // a quick tap that heard nothing
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
        List {
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
                        Text("\(Set(s.detections.map(\.scientific)).count) species · \(s.detections.count) detections")
                            .font(.caption).foregroundStyle(.secondary)
                        if !s.species.isEmpty {
                            Text(s.species.prefix(4).joined(separator: ", ") + (s.species.count > 4 ? "…" : ""))
                                .font(.caption).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m < 1 ? "<1 min" : m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }
}

struct SessionPage: View {
    let session: SessionSummary

    private struct Span: Identifiable { let id = UUID(); let name: String; let start: Date; let end: Date; let confirmed: Bool; var labeled = false }

    private var spans: [Span] {
        let minWidth = max(session.duration * 0.012, 4)
        var named = Set<String>()
        return session.detections.map {   // detections are sorted by time; label each species' first bar
            Span(name: $0.common, start: $0.firstHeard,
                 end: max($0.lastHeard.addingTimeInterval(5), $0.firstHeard.addingTimeInterval(minWidth)),
                 confirmed: $0.confirmed, labeled: named.insert($0.common).inserted)
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Length", value: SessionsList.duration(session.duration))
                LabeledContent("Species", value: "\(Set(session.detections.map(\.scientific)).count)")
                if let r = session.record, r.trackLat.count > 1 {
                    LabeledContent("Distance", value: Measurement(value: distance(r), unit: UnitLength.meters)
                        .formatted(.measurement(width: .abbreviated, usage: .road)))
                }
            }
            if hasMap {
                Section("Route") { routeMap.frame(height: 240).listRowInsets(EdgeInsets()) }
            }
            if !spans.isEmpty {
                Section("When each was heard") {
                    let names = session.species
                    Chart(spans) { s in
                        BarMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end), y: .value("Species", s.name), height: 8)
                            .foregroundStyle(s.confirmed ? Color.green : Color.accentColor)
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
        }
        .navigationTitle(session.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasMap: Bool { (session.record?.trackLat.count ?? 0) > 1 || session.detections.contains { $0.latitude != nil } }

    private var routeMap: some View {
        Map {
            if let r = session.record, r.trackLat.count > 1 {
                MapPolyline(coordinates: zip(r.trackLat, r.trackLon).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) })
                    .stroke(.blue, lineWidth: 4)
            }
            ForEach(session.detections.filter { $0.latitude != nil }) { d in
                Annotation(d.common, coordinate: CLLocationCoordinate2D(latitude: d.latitude!, longitude: d.longitude!)) {
                    Image(symbol: d.taxon.symbol).font(.caption2).padding(4)
                        .background(d.confirmed ? Color.green : Color.accentColor, in: Circle()).foregroundStyle(.white)
                }
            }
        }
    }

    private func distance(_ r: ListeningSession) -> Double {
        let pts = zip(r.trackLat, r.trackLon).map { CLLocation(latitude: $0, longitude: $1) }
        return zip(pts, pts.dropFirst()).reduce(0) { $0 + $1.0.distance(from: $1.1) }
    }
}
