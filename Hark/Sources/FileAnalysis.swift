import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers
import HarkCore
import MapKit
import CoreLocation

/// Reads any audio file iOS can decode as a stream of 32 kHz mono, a second at a time, so an hour-long
/// recording never has to fit in memory.
actor AudioFileReader {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 32_000, channels: 1, interleaved: false)!
    private var done = false
    let duration: TimeInterval

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        guard file.length > 0, let c = AVAudioConverter(from: file.processingFormat, to: out) else {
            throw NSError(domain: "Hark", code: 3, userInfo: [NSLocalizedDescriptionKey: "Hark can't read this kind of audio"])
        }
        converter = c
        duration = Double(file.length) / file.processingFormat.sampleRate
    }

    /// About the next second of audio; nil at the end.
    func next() -> [Float]? {
        guard !done else { return nil }
        let inFmt = file.processingFormat
        let want = AVAudioFrameCount(inFmt.sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: want) else { return nil }
        do { try file.read(into: buf, frameCount: want) } catch { done = true; return nil }
        if buf.frameLength == 0 { done = true; return nil }
        if buf.frameLength < want { done = true }
        guard let o = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: AVAudioFrameCount(Double(buf.frameLength) * 32_000 / inFmt.sampleRate) + 64) else { return nil }
        var fed = false
        var err: NSError?
        converter.convert(to: o, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        guard err == nil, let ch = o.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ch, count: Int(o.frameLength)))
    }
}

/// Analyze recordings from anywhere (a recorder's SD card, a voice memo, a trail-cam clip) exactly as if Hark had
/// been listening: the same models, thresholds and wait-before-logging rule, one check per second of the file. Each file
/// becomes a session in the Log; what's found is logged at the file's own date, with a clip, and no place.
@MainActor
@Observable
final class FileAnalysis {
    static let shared = FileAnalysis()

    struct Job: Identifiable {
        enum State: Equatable { case waiting, running(Double), done(species: Int, detections: Int, leftOut: Int), failed(String) }
        let id = UUID()
        let url: URL
        var name: String { url.lastPathComponent }
        var state: State = .waiting
        /// The Log session it became.
        var session: UUID?
    }

    private(set) var jobs: [Job] = []
    private(set) var running = false
    private var task: Task<Void, Never>?
    /// Where the recordings were made, so IDs can be checked against what lives there at that time of year.
    /// Unknown: no check, every confident ID is logged.
    enum Place: String, CaseIterable { case unknown, here, chosen }
    var place: Place = Place(rawValue: UserDefaults.standard.string(forKey: "filePlace") ?? "") ?? .unknown {
        didSet { UserDefaults.standard.set(place.rawValue, forKey: "filePlace") }
    }
    /// The last place picked (kept, since a recorder usually lives in one spot).
    var chosen: (latitude: Double, longitude: Double, name: String)? = {
        let d = UserDefaults.standard
        guard let n = d.string(forKey: "filePlaceName") else { return nil }
        return (d.double(forKey: "filePlaceLat"), d.double(forKey: "filePlaceLon"), n)
    }() {
        didSet {
            let d = UserDefaults.standard
            d.set(chosen?.name, forKey: "filePlaceName"); d.set(chosen?.latitude, forKey: "filePlaceLat"); d.set(chosen?.longitude, forKey: "filePlaceLon")
        }
    }
    /// When: each file's own date, or one date for all of them (recorders with a dead clock, files copied around).
    var useFileDate = true
    var date = Date()

    static let types: [UTType] = [.audio, .mpeg4Movie, .quickTimeMovie]

    var isIdle: Bool { !running && !jobs.contains { $0.state == .waiting } }

    func add(_ urls: [URL]) {
        let have = Set(jobs.map(\.url))
        jobs += urls.filter { !have.contains($0) }.map { Job(url: $0) }
    }

    /// A file handed to Hark from outside ("Open in Hark"): queue it and bring up the analysis screen.
    private(set) var arrivals = 0
    func receive(_ url: URL) { add([url]); arrivals += 1 }

    func clearFinished() { jobs.removeAll { if case .waiting = $0.state { false } else if case .running = $0.state { false } else { true } } }

    func cancel() { task?.cancel() }

    func start(_ listener: Listener) {
        guard !running, listener.state != .listening, listener.canListen else { return }
        running = true
        UIApplication.shared.isIdleTimerDisabled = true      // a long file shouldn't stall when the screen sleeps
        task = Task {
            while let i = jobs.firstIndex(where: { $0.state == .waiting }), !Task.isCancelled {
                await run(i, listener)
            }
            for i in jobs.indices where jobs[i].state == .waiting { jobs[i].state = .failed("Stopped") }
            running = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func run(_ i: Int, _ listener: Listener) async {
        let url = jobs[i].url
        jobs[i].state = .running(0)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let ctx = listener.modelContext, let labels = listener.labels else { jobs[i].state = .failed("Hark isn't ready yet"); return }
        let reader: AudioFileReader
        do { reader = try AudioFileReader(url: url) } catch { jobs[i].state = .failed(error.localizedDescription); return }

        // The file's own date if it has one (or the date given): detections land in the Log when the recording was made.
        let made = useFileDate ? ((try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .now) : date
        let duration = reader.duration
        let base = min(made, Date.now.addingTimeInterval(-duration))
        let sessionID = UUID()
        let rec = ListeningSession(id: sessionID, started: base)
        rec.kind = "file"; rec.title = url.deletingPathExtension().lastPathComponent; rec.ended = base.addingTimeInterval(duration)
        ctx.insert(rec)
        jobs[i].session = sessionID

        // Where and when it was recorded, if we were told: IDs that don't fit there are counted and left out.
        var spot: CLLocationCoordinate2D?
        switch place {
        case .unknown: break
        case .here: spot = listener.whereabouts
        case .chosen: spot = chosen.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        var check = Listener.Check.nothing
        if let spot, let c = await listener.expectations(latitude: spot.latitude, longitude: spot.longitude, date: base) {
            check = .place(c); rec.latitude = spot.latitude; rec.longitude = spot.longitude
        } else if place != .unknown { spot = nil }
        var leftOut = Set<Int>()

        let confirm = Listener.confirm(seconds: listener.confirmSeconds, interval: 1)
        var tracker = DetectionTracker(gap: 60, confirmWindows: confirm.windows, confirmSpan: confirm.span)
        var logged: [UUID: Detection] = [:], clipBest: [UUID: Float] = [:]
        let window = PerchClassifier.windowSamples
        var buffer: [Float] = [], heard = 0, scoredAt = 0

        func score(final: Bool) async {
            guard heard >= 32_000, let triage = await listener.identify(Array(buffer.suffix(window)), check: check) else { return }
            leftOut.formUnion(triage.unusual.map(\.index))
            let t = base.addingTimeInterval(Double(heard) / 32_000)
            for change in tracker.add(WindowResult(time: t, hits: triage.hits)) {
                switch change {
                case .started(let o):
                    guard labels[o.index].group.isSpecies, let d = listener.logFileDetection(o, session: sessionID, at: spot) else { continue }
                    logged[o.id] = d; clipBest[o.id] = o.bestConfidence
                    d.clipFile = await ClipStore.save(Array(buffer.suffix(window)))
                case .updated(let o):
                    guard let d = logged[o.id] else { continue }
                    d.lastHeard = o.lastHeard; d.windows = o.windows; d.confidence = Double(o.bestConfidence)
                    if o.bestConfidence >= (clipBest[o.id] ?? 0) + 0.05 {
                        clipBest[o.id] = o.bestConfidence
                        let old = d.clipFile
                        d.clipFile = await ClipStore.save(Array(buffer.suffix(window)))
                        ClipStore.delete(old)
                    }
                }
            }
        }

        while !Task.isCancelled, let chunk = await reader.next() {
            buffer += chunk; heard += chunk.count
            if buffer.count > window { buffer.removeFirst(buffer.count - window) }
            // From 5 s in, once per second of file; a shorter file is scored once, whole, at the end.
            if heard >= window, heard - scoredAt >= 32_000 { scoredAt = heard; await score(final: false) }
            jobs[i].state = .running(min(Double(heard) / 32_000 / max(duration, 1), 1))
        }
        if scoredAt == 0, !Task.isCancelled { await score(final: true) }

        if Task.isCancelled {
            rec.ended = base.addingTimeInterval(Double(heard) / 32_000)
            jobs[i].state = .failed("Stopped at \(SessionsList.clock(Double(heard) / 32_000)); what it found so far is in the Log")
        } else {
            let found = Set(logged.values.map(\.scientific))
            let out = leftOut.filter { !found.contains(labels[$0].scientific) }
            if !out.isEmpty {
                let names = out.map { labels[$0].displayName }.sorted()
                rec.note = "Left out as unlikely \(place == .here ? "here" : "there") at that time of year: " + names.joined(separator: ", ") + "."
            }
            jobs[i].state = .done(species: found.count, detections: logged.count, leftOut: out.count)
        }
        try? ctx.save()
        WidgetBridge.refresh(ctx, listening: false)
        // "Open in Hark" hands over a copy in the app's Inbox; it has done its job.
        if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
    }
}

/// Pick recordings, watch them go, open what each one found.
struct FileAnalysisView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    /// Results open right here, on top of the list of recordings, so Back returns to it.
    @State private var path = NavigationPath()
    @Query private var logged: [Detection]
    @Query private var records: [ListeningSession]
    @State private var picking = false
    @State private var pickingPlace = false
    private var files: FileAnalysis { .shared }

    var body: some View {
        @Bindable var files = FileAnalysis.shared
        NavigationStack(path: $path) {
            List { Group {
                Section {
                    Button { picking = true } label: { Label(files.jobs.isEmpty ? "Choose recordings…" : "Add more…", systemImage: "folder.badge.plus") }
                } footer: {
                    Text("Pick one file or many (WAV, FLAC, MP3, M4A, or the sound from a video). Hark listens to each from start to finish with your current model and pickiness, and saves what it finds as a session in the Log.")
                }
                Section {
                    Picker("Recorded", selection: $files.place) {
                        Text("Don't know").tag(FileAnalysis.Place.unknown)
                        Text("Here").tag(FileAnalysis.Place.here)
                        Text("Somewhere else").tag(FileAnalysis.Place.chosen)
                    }
                    .pickerStyle(.segmented)
                    if files.place == .chosen {
                        Button { pickingPlace = true } label: {
                            LabeledContent { Text(files.chosen?.name ?? "Choose…").lineLimit(1) } label: { Label("Place", systemImage: "mappin.and.ellipse") }
                        }
                    }
                    if files.place == .here && listener.whereabouts == nil {
                        Label("Hark doesn't know where the phone is yet. Allow location, or pick the place by hand.", systemImage: "location.slash").font(.caption).foregroundStyle(.orange)
                    }
                    if files.place != .unknown {
                        Toggle("Use each file's own date", isOn: $files.useFileDate)
                        if !files.useFileDate { DatePicker("Recorded on", selection: $files.date, in: ...Date.now, displayedComponents: .date) }
                    }
                } header: { Text("Where and when") } footer: {
                    Text(files.place == .unknown
                         ? "A file doesn't say where it was recorded. With no place, Hark logs every confident ID, wherever that species lives."
                         : "Hark checks each ID against the species found at that place at that time of year, as it does when you listen live. IDs that don't fit are left out of the Log and listed in the session's notes, so you can see what was dropped.")
                }
                .disabled(files.running)
                if !files.jobs.isEmpty {
                    Section {
                        ForEach(files.jobs) { j in row(j) }
                    } header: { Text("Recordings") } footer: {
                        if files.running { Text("Keep Hark open while it works: if you switch away it pauses, and carries on when you come back. An hour of audio takes a few minutes.") }
                    }
                    Section {
                        if files.running {
                            Button("Stop", role: .destructive) { files.cancel() }
                        } else {
                            if files.jobs.contains(where: { $0.state == .waiting }) {
                                Button { files.start(listener) } label: { Label("Analyze", systemImage: "waveform.badge.magnifyingglass").font(.headline) }
                                    .disabled(listener.state == .listening || !listener.canListen || (files.place == .chosen && files.chosen == nil))
                            }
                            if files.jobs.contains(where: { $0.state != .waiting }) { Button("Clear finished") { files.clearFinished() } }
                        }
                    } footer: {
                        if listener.state == .listening { Text("Stop listening first: the models do one thing at a time.") }
                    }
                }
            }.themedRows() }.themedList()
            .navigationTitle("Analyze recordings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SessionSummary.self) { SessionPage(session: $0) }
            .navigationDestination(for: Detection.self) { DetectionDetail(detection: $0) }
            .navigationDestination(for: SpeciesKey.self) { SpeciesPage(scientific: $0.scientific) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $pickingPlace) { PlacePicker(start: files.chosen ?? listener.whereabouts.map { ($0.latitude, $0.longitude, "") }) { files.chosen = $0 }.themeRoot() }
            .fileImporter(isPresented: $picking, allowedContentTypes: FileAnalysis.types, allowsMultipleSelection: true) { r in
                if case .success(let urls) = r { files.add(urls) }
            }
        }
        .environment(\.openDetection) { path.append($0) }      // map pins
    }

    @ViewBuilder private func row(_ j: FileAnalysis.Job) -> some View {
        switch j.state {
        case .waiting:
            LabeledContent { Text("Waiting").foregroundStyle(.secondary) } label: { Text(j.name).lineLimit(1).truncationMode(.middle) }
        case .running(let f):
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(j.name).lineLimit(1).truncationMode(.middle); Spacer(); Text("\(Int(f * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                ProgressView(value: f)
            }
        case .done(let species, let detections, let leftOut):
            Button {
                if let id = j.session, let s = SessionSummary.build(logged.filter { $0.sessionID == id }, records.filter { $0.id == id }).first { path.append(s) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(j.name).lineLimit(1).truncationMode(.middle).foregroundStyle(.primary)
                        Text((detections == 0 ? "Nothing identified" : "\(species) species · \(detections) detections") + (leftOut > 0 ? " · \(leftOut) left out as unlikely there" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if detections > 0 || leftOut > 0 { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
                }
            }
            .disabled(detections == 0 && leftOut == 0)
        case .failed(let why):
            VStack(alignment: .leading, spacing: 2) {
                Text(j.name).lineLimit(1).truncationMode(.middle)
                Text(why).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

/// Say where a recording was made: search for a town or a park, tap the map, or type coordinates.
struct PlacePicker: View {
    typealias Spot = (latitude: Double, longitude: Double, name: String)
    var start: Spot?
    var done: (Spot) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var latText = ""
    @State private var lonText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $position) {
                        if let pin { Marker(name.isEmpty ? "Recorded here" : name, coordinate: pin) }
                    }
                    .onTapGesture { p in if let c = proxy.convert(p, from: .local) { set(c, name: nil, move: false) } }
                }
                .overlay(alignment: .top) {
                    if !results.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(results.prefix(5), id: \.self) { item in
                                Button {
                                    set(item.placemark.coordinate, name: item.name, move: true); results = []
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(item.name ?? "Place").foregroundStyle(.primary)
                                        if let t = item.placemark.title { Text(t).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 8)
                                }
                                Divider()
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(10)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Latitude", text: $latText).keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $lonText).keyboardType(.numbersAndPunctuation)
                    Button("Go") {
                        if let a = Double(latText.trimmingCharacters(in: .whitespaces)), let b = Double(lonText.trimmingCharacters(in: .whitespaces)),
                           abs(a) <= 90, abs(b) <= 180 { set(CLLocationCoordinate2D(latitude: a, longitude: b), name: nil, move: true) }
                    }
                    .buttonStyle(.bordered)
                }
                .textFieldStyle(.roundedBorder).font(.callout.monospacedDigit())
                .padding(.horizontal).padding(.vertical, 10)
                Text(pin == nil ? "Search for a town or a park, tap the map, or type coordinates. Near enough is fine: Hark looks at what lives within a few miles." : (name.isEmpty ? "Looking up the name…" : name))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal).padding(.bottom, 10)
            }
            .navigationTitle("Where was it recorded?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Town, park, address")
            .onSubmit(of: .search) { search() }
            .onChange(of: query) { _, q in if q.isEmpty { results = [] } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        if let pin { done((pin.latitude, pin.longitude, name.isEmpty ? Self.coords(pin) : name)) }
                        dismiss()
                    }
                    .disabled(pin == nil)
                }
            }
            .onAppear {
                guard pin == nil, let s = start else { return }
                let c = CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
                if s.name.isEmpty { position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 60_000, longitudinalMeters: 60_000)) }   // just a starting view: where the phone is
                else { set(c, name: s.name, move: true) }
            }
        }
    }

    static func coords(_ c: CLLocationCoordinate2D) -> String { String(format: "%.3f, %.3f", c.latitude, c.longitude) }

    private func set(_ c: CLLocationCoordinate2D, name n: String?, move: Bool) {
        pin = c; name = n ?? ""
        latText = String(format: "%.4f", c.latitude); lonText = String(format: "%.4f", c.longitude)
        if move { position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 60_000, longitudinalMeters: 60_000)) }
        guard n == nil else { return }
        Task {   // a name for the pin: the town, or failing that the coordinates
            let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude))
            guard pin?.latitude == c.latitude, pin?.longitude == c.longitude else { return }
            let m = marks?.first
            name = [m?.locality ?? m?.name, m?.administrativeArea].compactMap { $0 }.joined(separator: ", ")
            if name.isEmpty { name = Self.coords(c) }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        // "44.47, -89.53" typed into the search box works too
        let parts = q.split(whereSeparator: { ", ".contains($0) }).compactMap { Double($0) }
        if parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 {
            set(CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1]), name: nil, move: true); return
        }
        let req = MKLocalSearch.Request(); req.naturalLanguageQuery = q
        Task { results = (try? await MKLocalSearch(request: req).start())?.mapItems ?? [] }
    }
}
