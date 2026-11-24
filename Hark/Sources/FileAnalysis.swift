import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers
import HarkCore

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
/// been listening: the same models, thresholds and "hear it for" rule, one check per second of the file. Each file
/// becomes a session in the Log; what's found is logged at the file's own date, with a clip, and no place.
@MainActor
@Observable
final class FileAnalysis {
    static let shared = FileAnalysis()

    struct Job: Identifiable {
        enum State: Equatable { case waiting, running(Double), done(species: Int, detections: Int), failed(String) }
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
    /// The recordings were made around here, around now: check IDs against place and season like a live session.
    var local = false

    static let types: [UTType] = [.audio, .mpeg4Movie, .quickTimeMovie]

    var isIdle: Bool { !running && !jobs.contains { $0.state == .waiting } }

    func add(_ urls: [URL]) {
        let have = Set(jobs.map(\.url))
        jobs += urls.filter { !have.contains($0) }.map { Job(url: $0) }
    }

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

        // The file's own date if it has one: detections land in the Log when the recording was made.
        let made = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .now
        let duration = reader.duration
        let base = min(made, Date.now.addingTimeInterval(-duration))
        let sessionID = UUID()
        let rec = ListeningSession(id: sessionID, started: base)
        rec.kind = "file"; rec.title = url.deletingPathExtension().lastPathComponent; rec.ended = base.addingTimeInterval(duration)
        ctx.insert(rec)
        jobs[i].session = sessionID

        let confirm = Listener.confirm(seconds: listener.confirmSeconds, interval: 1)
        var tracker = DetectionTracker(gap: 60, confirmWindows: confirm.windows, confirmSpan: confirm.span)
        var logged: [UUID: Detection] = [:], clipBest: [UUID: Float] = [:]
        let window = PerchClassifier.windowSamples
        var buffer: [Float] = [], heard = 0, scoredAt = 0

        func score(final: Bool) async {
            guard heard >= 32_000, let triage = await listener.identify(Array(buffer.suffix(window)), local: local) else { return }
            let t = base.addingTimeInterval(Double(heard) / 32_000)
            for change in tracker.add(WindowResult(time: t, hits: triage.hits)) {
                switch change {
                case .started(let o):
                    guard labels[o.index].group.isSpecies, let d = listener.logFileDetection(o, session: sessionID) else { continue }
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
            jobs[i].state = .done(species: Set(logged.values.map(\.scientific)).count, detections: logged.count)
        }
        try? ctx.save()
        WidgetBridge.refresh(ctx, listening: false)
    }
}

/// Pick recordings, watch them go, open what each one found.
struct FileAnalysisView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    /// Open a finished file's session in the Log.
    var open: (UUID) -> Void = { _ in }
    @State private var picking = false
    private var files: FileAnalysis { .shared }

    var body: some View {
        @Bindable var files = FileAnalysis.shared
        NavigationStack {
            List { Group {
                Section {
                    Button { picking = true } label: { Label(files.jobs.isEmpty ? "Choose recordings…" : "Add more…", systemImage: "folder.badge.plus") }
                    Toggle("Recorded around here, this season", isOn: $files.local).disabled(files.running)
                } footer: {
                    Text("Pick one file or many (WAV, FLAC, MP3, M4A, or the sound from a video). Hark listens to each from start to finish with your current model and pickiness, and saves what it finds as a session in the Log, dated when the file was made. Leave the switch off for recordings from somewhere else or another time of year: on, IDs that don't fit here and now are dropped, as they are when you listen live.")
                }
                if !files.jobs.isEmpty {
                    Section {
                        ForEach(files.jobs) { j in row(j) }
                    } header: { Text("Recordings") } footer: {
                        if files.running { Text("Keep Hark open while it works. An hour of audio takes a few minutes.") }
                    }
                    Section {
                        if files.running {
                            Button("Stop", role: .destructive) { files.cancel() }
                        } else {
                            if files.jobs.contains(where: { $0.state == .waiting }) {
                                Button { files.start(listener) } label: { Label("Analyze", systemImage: "waveform.badge.magnifyingglass").font(.headline) }
                                    .disabled(listener.state == .listening || !listener.canListen)
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: FileAnalysis.types, allowsMultipleSelection: true) { r in
                if case .success(let urls) = r { files.add(urls) }
            }
        }
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
        case .done(let species, let detections):
            Button { if let s = j.session { open(s) } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(j.name).lineLimit(1).truncationMode(.middle).foregroundStyle(.primary)
                        Text(detections == 0 ? "Nothing identified" : "\(species) species · \(detections) detections")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if detections > 0 { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
                }
            }
            .disabled(detections == 0)
        case .failed(let why):
            VStack(alignment: .leading, spacing: 2) {
                Text(j.name).lineLimit(1).truncationMode(.middle)
                Text(why).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
