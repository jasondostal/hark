import Foundation
import Observation
import SwiftData
import UIKit
import HarkCore
import CoreML

/// Holds the newest 60 s of 32 kHz audio (Rewind reaches back this far). Appended synchronously on the audio thread (so chunks stay in order;
/// hopping through Tasks could reorder them), read by the scoring loop.
final class AudioStore: @unchecked Sendable {
    static let seconds = 60
    private var ring = RingBuffer(capacity: 32_000 * seconds)
    private let lock = NSLock()
    func append(_ s: [Float]) { lock.lock(); ring.append(s); lock.unlock() }
    func latest(_ n: Int) -> [Float] { lock.lock(); defer { lock.unlock() }; return ring.latest(n) }
    var count: Int { lock.lock(); defer { lock.unlock() }; return ring.count }
    func reset() { lock.lock(); ring.removeAll(); lock.unlock() }
}

/// Runs Perch off the main thread, one window at a time.
actor Inference {
    let classifier: PerchClassifier
    init(_ c: PerchClassifier) { classifier = c }
    func classify(_ w: [Float]) throws -> PerchClassifier.Output { try classifier.classify(w) }
}

/// A frozen copy of recent audio for Rewind. `end` is when the last sample was heard.
struct RewindClip: Identifiable {
    let id = UUID()
    let samples: [Float]
    let end: Date
    var duration: TimeInterval { Double(samples.count) / 32_000 }
    func time(atSample i: Int) -> Date { end.addingTimeInterval(-Double(samples.count - i) / 32_000) }
}

/// Heard in the last 15 s but not logged automatically: under the threshold ("maybe"),
/// or confident but never recorded near you ("unusual here").
struct Maybe: Identifiable, Equatable {
    let index: Int
    var unusual = false
    var best: Float
    var firstSeen: Date
    var lastSeen: Date
    var id: Int { index }
}

@MainActor
@Observable
final class Listener {
    static let shared = Listener()
    enum State: Equatable { case loading, ready, listening, failed(String) }

    private(set) var state: State = .loading
    private(set) var labels: LabelTable?
    private(set) var hearingNow: [DetectionTracker.Occurrence] = []
    private(set) var session: [DetectionTracker.Occurrence] = []
    private(set) var maybes: [Maybe] = []         // includes the "unusual here" ones (flagged)
    private(set) var manual: [Detection] = []     // logged by hand from a maybe, this session
    let live = LiveSpectrogram()
    private(set) var levelDB: Float = -120
    private(set) var lastInferenceMs: Double = 0

    // Settings (persisted)
    var policy: DetectionPolicy = UserDefaults.standard.data(forKey: "policy")
        .flatMap { try? JSONDecoder().decode(DetectionPolicy.self, from: $0) } ?? DetectionPolicy() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(policy), forKey: "policy") }
    }
    /// Muted species, by scientific name (stable if the label table changes).
    private(set) var mutedNames: [String] = UserDefaults.standard.stringArray(forKey: "muted") ?? [] {
        didSet { UserDefaults.standard.set(mutedNames, forKey: "muted"); refreshMuted() }
    }
    private var muted: Set<Int> = []

    // Location filter
    private var ranges: RangeMap?
    private(set) var localRange: LocalRange?
    var rangeAvailable: Bool { ranges != nil }

    private var inference: Inference?
    private let store = AudioStore()
    private let audio = AudioCapture()
    private let location = LocationProvider()
    private var tracker = DetectionTracker(gap: 60)
    private var loop: Task<Void, Never>?
    private var sessionID = UUID()
    private var logged: [UUID: Detection] = [:]   // occurrence id -> its log row
    private var recentMaybes: [Int: Maybe] = [:]
    private var manualIndices: Set<Int> = []
    private var clipBest: [UUID: Float] = [:]      // occurrence id -> confidence of its saved clip
    private var quietUntil = Date.distantPast     // ignore the mic while Hark plays audio
    var modelContext: ModelContext?
    var rewind: RewindClip?
    private var pendingStart = false
    private var startedAt = Date()
    private var sessionSpecies: Set<Int> = []
    private let liveActivity = LiveActivityController()

    // Listening options (persisted)
    var keepScreenOn: Bool = UserDefaults.standard.object(forKey: "keepScreenOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepScreenOn, forKey: "keepScreenOn")
                 if state == .listening { UIApplication.shared.isIdleTimerDisabled = keepScreenOn } }
    }
    /// Safety net for walk mode: stop after this many minutes (0 = never).
    var stopAfterMinutes: Int = UserDefaults.standard.object(forKey: "stopAfterMinutes") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(stopAfterMinutes, forKey: "stopAfterMinutes") }
    }

    /// Action Button / Control Center / Siri: start now, or as soon as the model has loaded.
    func requestStart() async {
        switch state {
        case .ready: await start()
        case .loading: pendingStart = true
        default: break
        }
    }

    init() {
        ClipPlayer.shared.onPlay = { [weak self] d in self?.quietUntil = .now.addingTimeInterval(d + 5.5) }
    }

    static let hop: Duration = .seconds(1)

    func loadModel() async {
        guard inference == nil else { return }
        do {
            guard let modelURL = Bundle.main.url(forResource: "Perch", withExtension: "mlmodelc"),
                  let labelsURL = Bundle.main.url(forResource: "labels", withExtension: "json") else {
                state = .failed("Model files missing from the app bundle"); return
            }
            let rangesURL = Bundle.main.url(forResource: "ranges", withExtension: "bin")
            let (clf, table, rm) = try await Task.detached(priority: .userInitiated) {
                #if targetEnvironment(simulator)
                let units: MLComputeUnits = .cpuOnly   // simulator: no ANE, and its GPU path gives wrong answers
                #else
                let units: MLComputeUnits = .cpuAndNeuralEngine   // device: ANE; no GPU, so it keeps working in the background
                #endif
                let c = try PerchClassifier(url: modelURL, computeUnits: units)
                _ = try c.classify([Float](repeating: 0, count: PerchClassifier.windowSamples))   // warm up / ANE compile
                return (c, try LabelTable(contentsOf: labelsURL), rangesURL.flatMap { try? RangeMap(contentsOf: $0) })
            }.value
            inference = Inference(clf); labels = table; ranges = rm
            refreshMuted()
            state = .ready
            if pendingStart { pendingStart = false; await start() }
        } catch {
            state = .failed("Couldn't load Perch: \(error.localizedDescription)")
        }
    }

    func label(_ i: Int) -> HarkCore.Label? { labels.map { $0[i] } }

    func toggle() async { state == .listening ? stop() : await start() }

    func start() async {
        guard state == .ready, inference != nil else { return }
        let feeding = ProcessInfo.processInfo.arguments.contains("-feedfile")
        let allowed = feeding ? true : await AudioCapture.requestPermission()
        guard allowed else {
            state = .failed("Microphone access is off. Turn it on in Settings > Hark."); return
        }
        sessionID = UUID(); tracker.reset(); logged = [:]; clipBest = [:]; hearingNow = []; session = []
        sessionSpecies = []; startedAt = .now
        recentMaybes = [:]; maybes = []; manual = []; manualIndices = []
        store.reset(); live.reset()
        let store = self.store, live = self.live
        audio.onSamples = { [weak self] s, db in
            store.append(s)
            live.append(s)
            Task { @MainActor in self?.levelDB = db }
        }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-feedfile"), i + 1 < args.count {
            audio.startFiles(args[i + 1].split(separator: ",").map { URL(fileURLWithPath: String($0)) })
        } else { do { try audio.start() } catch {
            state = .failed("Couldn't start the microphone: \(error.localizedDescription)"); return
        } }
        location.start(background: true)
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        state = .listening
        liveActivity.start()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hop)
                guard let self else { return }
                if self.stopAfterMinutes > 0, Date().timeIntervalSince(self.startedAt) > Double(self.stopAfterMinutes) * 60 {
                    self.stop(); return
                }
                await self.scoreLatest()
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        audio.stop(); location.stop()
        liveActivity.end()
        UIApplication.shared.isIdleTimerDisabled = false
        if state == .listening { state = .ready }
        hearingNow = []; maybes = []
    }

    private func refreshMuted() {
        guard let labels else { return }
        let names = Set(mutedNames)
        muted = Set(labels.labels.indices.filter { names.contains(labels[$0].scientific) })
    }

    /// "Never show this species": drops it from the screen now and from scoring from here on.
    func mute(_ index: Int) {
        guard let l = label(index), !mutedNames.contains(l.scientific) else { return }
        mutedNames.append(l.scientific)
        hearingNow.removeAll { $0.index == index }
        maybes.removeAll { $0.index == index }; recentMaybes[index] = nil
    }
    func unmute(_ scientific: String) { mutedNames.removeAll { $0 == scientific } }
    func commonName(_ scientific: String) -> String {
        labels?.labels.first { $0.scientific == scientific }?.common ?? scientific
    }

    /// Recompute the local species list when you move into a new grid cell (~150 km).
    private func updateRange() {
        guard let ranges, let loc = location.last else { return }
        let c = ranges.cell(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        if localRange?.cell != c { localRange = ranges.local(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude) }
    }

    /// Score the newest 5 s. Runs about once a second, so each sound is seen in ~5 overlapping windows.
    private func scoreLatest() async {
        guard let inference, let labels, state == .listening else { return }
        guard store.count >= 32_000 * 2 else { return }   // wait for 2 s of audio
        guard Date() >= quietUntil else { return }         // playing a clip: the mic hears the speaker
        let w = store.latest(PerchClassifier.windowSamples)
        let t0 = Date()
        guard let out = try? await inference.classify(w) else { return }
        lastInferenceMs = Date().timeIntervalSince(t0) * 1000
        let scores = Scoring.softmax(out.logits)
        updateRange()
        let triage = policy.triage(scores: scores, labels: labels, range: localRange, muted: muted)
        let result = WindowResult(time: .now, hits: triage.hits)
        if ProcessInfo.processInfo.arguments.contains("-autolisten") {
            NSLog("HARK-WINDOW %.0f ms: %@", lastInferenceMs, result.hits.map { "\(labels[$0.index].common) \(Int($0.confidence * 100))%" }.joined(separator: ", "))
        }
        for change in tracker.add(result) { log(change, labels) }
        hearingNow = tracker.active(at: .now)
        session = tracker.occurrences.sorted { $0.firstHeard > $1.firstHeard }
        updateMaybes(triage, at: result.time)
    }

    private func updateMaybes(_ t: DetectionPolicy.Triage, at now: Date) {
        let known = Set(tracker.occurrences.map(\.index)).union(manualIndices)
        let fresh = t.unusual.map { ($0.index, $0.confidence, true) } + t.maybes.map { ($0.index, $0.confidence, false) }
        for (i, p, unusual) in fresh where !known.contains(i) {
            if var m = recentMaybes[i] {
                m.best = max(m.best, p); m.lastSeen = now; m.unusual = m.unusual || unusual; recentMaybes[i] = m
            } else { recentMaybes[i] = Maybe(index: i, unusual: unusual, best: p, firstSeen: now, lastSeen: now) }
        }
        recentMaybes = recentMaybes.filter { now.timeIntervalSince($0.value.lastSeen) < 15 && !known.contains($0.key) && !muted.contains($0.key) }
        // unusual first (they were confident), then maybes by score
        maybes = recentMaybes.values.sorted { ($0.unusual ? 1 : 0, $0.best) > ($1.unusual ? 1 : 0, $1.best) }.prefix(5).map { $0 }
    }

    private func log(_ change: DetectionTracker.Change, _ labels: LabelTable) {
        guard let ctx = modelContext else { return }
        switch change {
        case .started(let o):
            let l = labels[o.index]
            guard l.group.isSpecies else { return }     // never log "Car passing by"
            let loc = location.last?.coordinate
            let d = Detection(label: l, confidence: Double(o.bestConfidence), at: o.firstHeard,
                              latitude: loc?.latitude, longitude: loc?.longitude, sessionID: sessionID, source: "live")
            let firstEver = markIfNew(d)
            ctx.insert(d); logged[o.id] = d
            if sessionSpecies.insert(o.index).inserted {
                newSpeciesHeard(l, firstEver: firstEver)
            }
            saveClip(for: d, occurrence: o)
        case .updated(let o):
            guard let d = logged[o.id] else { return }
            d.lastHeard = o.lastHeard; d.windows = o.windows; d.confidence = Double(o.bestConfidence)
            if o.bestConfidence >= (clipBest[o.id] ?? 0) + 0.05 { saveClip(for: d, occurrence: o) }
        }
    }

    /// Keep the 5 s window Perch was most confident about as the detection's clip.
    private func saveClip(for d: Detection, occurrence o: DetectionTracker.Occurrence) {
        clipBest[o.id] = o.bestConfidence
        let audio = store.latest(PerchClassifier.windowSamples)
        Task {
            guard let name = await ClipStore.save(audio) else { return }
            let old = d.clipFile
            d.clipFile = name
            if old != name { ClipStore.delete(old) }
        }
    }

    // MARK: Rewind

    var canRewind: Bool { state == .listening || store.count >= 32_000 }

    /// Freeze the last minute for Rewind.
    func openRewind() {
        let n = min(store.count, 32_000 * AudioStore.seconds)
        guard n >= 32_000 else { return }
        rewind = RewindClip(samples: store.latest(n), end: .now)
    }

    /// Score any stretch of audio: 5 s windows (padded or overlapping), best score per class across windows.
    func analyze(_ samples: [Float]) async -> DetectionPolicy.Triage? {
        guard let inference, let labels else { return nil }
        var rows: [[Float]] = []
        for st in Windowing.starts(length: samples.count) {
            guard let out = try? await inference.classify(Windowing.window(samples, start: st)) else { continue }
            rows.append(Scoring.softmax(out.logits))
        }
        guard !rows.isEmpty else { return nil }
        updateRange()
        return policy.triage(scores: Windowing.maxPool(rows), labels: labels, range: localRange, muted: muted, topK: 15)
    }

    /// Log a species picked out in Rewind, with the selection as its clip.
    func logSelection(_ index: Int, confidence: Float, samples: [Float], at: Date, confirmed: Bool) {
        guard let ctx = modelContext, let l = label(index) else { return }
        let loc = location.last?.coordinate
        let d = Detection(label: l, confidence: Double(confidence), at: at,
                          latitude: loc?.latitude, longitude: loc?.longitude, sessionID: sessionID, source: "rewind")
        d.confirmed = confirmed
        markIfNew(d)
        ctx.insert(d)
        manual.insert(d, at: 0); manualIndices.insert(index)
        let clip = Array(samples.suffix(32_000 * 15))
        Task { d.clipFile = await ClipStore.save(clip) }
    }

    func detection(for o: DetectionTracker.Occurrence) -> Detection? { logged[o.id] }

    /// "New for you!": flag the first-ever detection of a species, celebrate it on screen (or on the Lock Screen).
    private(set) var celebration: (id: UUID, name: String)?
    @discardableResult
    private func markIfNew(_ d: Detection) -> Bool {
        guard let ctx = modelContext else { return false }
        let s = d.scientific
        let n = (try? ctx.fetchCount(FetchDescriptor<Detection>(predicate: #Predicate { $0.scientific == s }))) ?? 1
        guard n == 0 else { return false }
        d.isFirst = true
        let c = (UUID(), d.common)
        celebration = c
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { try? await Task.sleep(for: .seconds(5)); if celebration?.id == c.0 { celebration = nil } }
        return true
    }

    /// First time a species is heard this session: a tap in the hand, and the Live Activity updates
    /// (lighting the Lock Screen and buzzing if Hark is in the background).
    private func newSpeciesHeard(_ l: HarkCore.Label, firstEver: Bool) {
        if !firstEver, UIApplication.shared.applicationState == .active {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        liveActivity.newSpecies(l.common, symbol: l.group.symbol, count: sessionSpecies.count, firstEver: firstEver)
    }

    /// Log a maybe by hand ("Log", or "I saw it" = logged and confirmed).
    func logMaybe(_ m: Maybe, confirmed: Bool) {
        guard let ctx = modelContext, let l = label(m.index) else { return }
        let loc = location.last?.coordinate
        let d = Detection(label: l, confidence: Double(m.best), at: m.firstSeen,
                          latitude: loc?.latitude, longitude: loc?.longitude, sessionID: sessionID, source: m.unusual ? "unusual" : "maybe")
        d.lastHeard = m.lastSeen
        d.confirmed = confirmed
        markIfNew(d)
        ctx.insert(d)
        manual.insert(d, at: 0); manualIndices.insert(m.index)
        let secs = min(15, Date().timeIntervalSince(m.firstSeen) + 5)
        let clip = store.latest(Int(secs * 32_000))
        Task { d.clipFile = await ClipStore.save(clip) }
        recentMaybes[m.index] = nil
        maybes.removeAll { $0.index == m.index }
    }
}
