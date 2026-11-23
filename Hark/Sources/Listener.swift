import Foundation
import Observation
import SwiftData
import UIKit
import HarkCore
import CoreML
import CoreLocation

/// Holds the newest 60 s of 32 kHz audio (touch-to-select reaches back this far). Appended synchronously on the audio thread (so chunks stay in order;
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

/// BirdNET+ V3.0 off the main thread, plus the map from its outputs to Hark's labels.
actor BirdNETInference {
    let classifier: BirdNET3Classifier
    let map: [UInt16]
    init(_ c: BirdNET3Classifier, map: [UInt16]) { classifier = c; self.map = map }

    /// Best score per Hark label (on Hark's scale) over 3 s windows covering `samples`.
    func scores(_ samples: [Float], labelCount: Int) throws -> [Float] {
        let n = BirdNET3Classifier.windowSamples
        var best: [Float]?
        for st in Windowing.starts(length: samples.count, window: n, hop: n / 2) {
            let s = try classifier.classify(Windowing.window(samples, start: st, window: n))
            if best == nil { best = s } else { for k in s.indices where s[k] > best![k] { best![k] = s[k] } }
        }
        var out = [Float](repeating: 0, count: labelCount)
        guard let best else { return out }
        for (j, b) in best.enumerated() where j < map.count && map[j] != 0xFFFF {
            let i = Int(map[j]); if i < labelCount { out[i] = max(out[i], Fusion.perchEquivalent(b)) }
        }
        return out
    }
}

/// A frozen copy of recent audio for touch-to-select. `end` is when the last sample was heard.
struct AudioSnapshot: Identifiable {
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
    /// Auto: Perch checks every second and logs what it hears. Manual: nothing is identified until you select it.
    enum IDMode: String { case auto, manual }

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
    var policy: DetectionPolicy = Listener.loadPolicy() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(policy), forKey: "policy") }
    }
    /// Saved settings from before the BirdNET-style scale move onto the new presets (once).
    private static func loadPolicy() -> DetectionPolicy {
        let d = UserDefaults.standard
        var p = d.data(forKey: "policy").flatMap { try? JSONDecoder().decode(DetectionPolicy.self, from: $0) } ?? DetectionPolicy()
        if d.integer(forKey: "policyVersion") < 2 {
            p.migrateLegacyPresets()
            d.set(try? JSONEncoder().encode(p), forKey: "policy"); d.set(2, forKey: "policyVersion")
        }
        return p
    }
    /// Show plain maybes (under the bar, not logged). Off by default: in a quiet room they're mostly noise.
    var showMaybes: Bool = UserDefaults.standard.bool(forKey: "showMaybes") {
        didSet { UserDefaults.standard.set(showMaybes, forKey: "showMaybes"); if !showMaybes { maybes.removeAll { !$0.unusual } } }
    }
    private var humanSoundIndices: [Int] = []
    private var synonymIndices: [(species: Int, sounds: [Int])]?
    /// Muted species, by scientific name (stable if the label table changes).
    private(set) var mutedNames: [String] = UserDefaults.standard.stringArray(forKey: "muted") ?? [] {
        didSet { UserDefaults.standard.set(mutedNames, forKey: "muted"); refreshMuted() }
    }
    private var muted: Set<Int> = []
    /// "Not it" this session: wrong IDs the person waved off (a 2 a.m. siren isn't a screech owl), ignored until the next Listen.
    private(set) var notHere: Set<Int> = []
    private var hidden: Set<Int> { notHere.isEmpty ? muted : muted.union(notHere) }

    // Location + season filter (see LocalContext): GBIF range map, BirdNET geomodel, your patch, eBird.
    private var ranges: RangeMap?
    private(set) var localRange: LocalRange?
    var rangeAvailable: Bool { ranges != nil }
    private var geo: GeoModel?
    var geoAvailable: Bool { geo != nil }
    let ebird = EBird()
    private(set) var context: LocalContext?
    private var geoExpectations: LocalContext.Geo?
    private var geoKey: String?
    private var geoRunning = false
    private(set) var patch: Set<Int> = []
    private var patchAt: CLLocation?

    private var inference: Inference?
    private var birdnet: BirdNETInference?
    private var birdnetLoading = false
    /// Hits both models backed this session (Both mode), for the "both models" tag.
    private(set) var agreed: Set<Int> = []
    /// Which model(s) identify: Perch, BirdNET+, or both in tandem.
    var model: Fusion.Model = Fusion.Model(rawValue: UserDefaults.standard.string(forKey: "model") ?? "") ?? .both {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "model"); Task { await loadBirdNETIfNeeded() } }
    }
    var birdnetAvailable: Bool { BirdNET3Classifier.bundledURL != nil }
    private let store = AudioStore()
    private let audio = AudioCapture()
    private let location = LocationProvider()
    private var tracker = DetectionTracker(gap: 60, confirmWindows: Listener.storedConfirmSeconds, confirmSpan: TimeInterval(max(5, Listener.storedConfirmSeconds + 2)))
    private static var storedConfirmSeconds: Int { max(1, UserDefaults.standard.object(forKey: "confirmSeconds") as? Int ?? 2) }
    /// Seconds (scored windows) a new species must be heard, within a few seconds, before it's logged. More = fewer
    /// one-off false IDs, a little slower; a bird that calls once, briefly, can be missed (touch the spectrogram).
    var confirmSeconds: Int = Listener.storedConfirmSeconds {
        didSet {
            UserDefaults.standard.set(confirmSeconds, forKey: "confirmSeconds")
            tracker.confirmWindows = confirmSeconds; tracker.confirmSpan = TimeInterval(max(5, confirmSeconds + 2))
        }
    }
    private var loop: Task<Void, Never>?
    private var sessionID = UUID()
    private var logged: [UUID: Detection] = [:]   // occurrence id -> its log row
    private var recentMaybes: [Int: Maybe] = [:]
    private var manualIndices: Set<Int> = []
    private var clipBest: [UUID: Float] = [:]      // occurrence id -> confidence of its saved clip
    private var quietUntil = Date.distantPast     // ignore the mic while Hark plays audio
    var modelContext: ModelContext?
    let selection = Selection()
    private var pendingStart = false
    private var startedAt = Date()
    private var sessionSpecies: Set<Int> = []
    private let liveActivity = LiveActivityController()
    private var sessionRecord: ListeningSession?
    private var lastTrackPoint: CLLocation?

    // Listening options (persisted)
    var keepScreenOn: Bool = UserDefaults.standard.object(forKey: "keepScreenOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepScreenOn, forKey: "keepScreenOn")
                 if state == .listening { UIApplication.shared.isIdleTimerDisabled = keepScreenOn } }
    }
    // Spectrogram + audio options (persisted)
    var palette: SpectrogramPalette = SpectrogramPalette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "") ?? .aurora {
        didSet { UserDefaults.standard.set(palette.rawValue, forKey: "palette"); SpectrogramStyle.shared.set(palette: palette) }
    }
    var contrast: Double = UserDefaults.standard.object(forKey: "contrast") as? Double ?? 0.6 {
        didSet { UserDefaults.standard.set(contrast, forKey: "contrast"); SpectrogramStyle.shared.set(contrast: contrast) }
    }
    var idMode: IDMode = IDMode(rawValue: UserDefaults.standard.string(forKey: "idMode") ?? "") ?? .auto {
        didSet {
            UserDefaults.standard.set(idMode.rawValue, forKey: "idMode")
            if idMode == .manual { hearingNow = []; maybes = []; recentMaybes = [:] }
        }
    }
    /// Seconds of audio across the live spectrogram.
    var spectrogramSeconds: Int = UserDefaults.standard.object(forKey: "spectrogramSeconds") as? Int ?? 10 {
        didSet { UserDefaults.standard.set(spectrogramSeconds, forKey: "spectrogramSeconds"); live.setSeconds(shownSeconds) }
    }
    /// Spectrogram width over its portrait width: landscape shows proportionally more time at the same detail.
    var widthScale = 1.0 { didSet { if shownSeconds != Self.seconds(spectrogramSeconds, oldValue) { live.setSeconds(shownSeconds) } } }
    var shownSeconds: Int { Self.seconds(spectrogramSeconds, widthScale) }
    private static func seconds(_ s: Int, _ scale: Double) -> Int {
        min(max(Int((Double(s) * max(scale, 1)).rounded()), s), LiveSpectrogram.maxSeconds)
    }
    var frequencyLabels: Bool = UserDefaults.standard.object(forKey: "frequencyLabels") as? Bool ?? true {
        didSet { UserDefaults.standard.set(frequencyLabels, forKey: "frequencyLabels") }
    }
    /// High-pass cutoff in Hz (0 = off): 80 trims wind and handling noise, 200 trims road rumble.
    var rumbleFilter: Double = UserDefaults.standard.object(forKey: "rumbleFilter") as? Double ?? 0 {
        didSet { UserDefaults.standard.set(rumbleFilter, forKey: "rumbleFilter"); audio.setHighPass(rumbleFilter) }
    }
    /// Preferred input port UID (nil = automatic). Applies next time listening starts.
    var inputUID: String? = UserDefaults.standard.string(forKey: "inputUID") {
        didSet { UserDefaults.standard.set(inputUID, forKey: "inputUID"); audio.preferredInputUID = inputUID }
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
        SpectrogramStyle.shared.set(palette: palette)
        SpectrogramStyle.shared.set(contrast: contrast)
        live.setSeconds(shownSeconds)
        audio.setHighPass(rumbleFilter)
        audio.preferredInputUID = inputUID
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
                return (c, try HarkCore.Label.table ?? LabelTable(contentsOf: labelsURL), rangesURL.flatMap { try? RangeMap(contentsOf: $0) })
            }.value
            inference = Inference(clf); labels = table; ranges = rm
            geo = await Task.detached(priority: .utility) { GeoModel() }.value
            await loadBirdNETIfNeeded()
            updateContext()
            refreshMuted()
            state = .ready
            if pendingStart { pendingStart = false; await start() }
        } catch {
            state = .failed("Couldn't load Perch: \(error.localizedDescription)")
        }
    }

    func label(_ i: Int) -> HarkCore.Label? { labels.map { $0[i] } }

    /// Load BirdNET+ the first time a mode needs it (it stays loaded after).
    func loadBirdNETIfNeeded() async {
        guard model != .perch, birdnet == nil, !birdnetLoading, let url = BirdNET3Classifier.bundledURL,
              let mapURL = Bundle.main.url(forResource: "birdnet3_map", withExtension: "bin") else { return }
        birdnetLoading = true; defer { birdnetLoading = false }
        birdnet = await Task.detached(priority: .userInitiated) { () -> BirdNETInference? in
            #if targetEnvironment(simulator)
            let units: MLComputeUnits = .cpuOnly
            #else
            let units: MLComputeUnits = .cpuAndNeuralEngine
            #endif
            guard let c = try? BirdNET3Classifier(url: url, computeUnits: units), let d = try? Data(contentsOf: mapURL) else { return nil }
            _ = try? c.classify([Float](repeating: 0, count: BirdNET3Classifier.windowSamples))   // warm up
            let map = d.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)).map { UInt16(littleEndian: $0) } }
            return BirdNETInference(c, map: map)
        }.value
    }

    /// Score audio with the chosen model(s) and triage it. Perch scores are padded to the full label table
    /// (BirdNET+-only species score 0 for Perch, and vice versa).
    private func identify(_ samples: [Float], topK: Int = 12) async -> DetectionPolicy.Triage? {
        guard let inference, let labels else { return nil }
        let n = labels.count
        var perch: [Float]?
        var human: Float = 0
        if model != .birdnet || birdnet == nil {
            var rows: [[Float]] = []
            for st in Windowing.starts(length: samples.count) {
                guard let out = try? await inference.classify(Windowing.window(samples, start: st)) else { continue }
                rows.append(Scoring.softmax(out.logits))
            }
            guard !rows.isEmpty else { return nil }
            var p = Windowing.maxPool(rows); if p.count < n { p += [Float](repeating: 0, count: n - p.count) }
            if synonymIndices == nil { synonymIndices = Fusion.synonymIndices(labels) }
            Fusion.poolSynonyms(&p, synonymIndices ?? [])
            if humanSoundIndices.isEmpty { humanSoundIndices = Fusion.humanSoundClasses.compactMap { labels.index(ofScientific: $0) } }
            human = humanSoundIndices.reduce(0) { $0 + p[$1] }
            perch = p
        }
        var bn: [Float]?
        if model != .perch, let birdnet { bn = try? await birdnet.scores(samples, labelCount: n) }
        updateContext()
        switch (perch, bn) {
        case let (p?, b?): return policy.triage(scores: p, second: b, labels: labels, context: context, muted: hidden, topK: topK, humanSound: human)
        case let (p?, nil): return policy.triage(scores: p, labels: labels, context: context, muted: hidden, topK: topK, humanSound: human)
        case let (nil, b?): return policy.triage(scores: b, labels: labels, context: context, muted: hidden, topK: topK)
        default: return nil
        }
    }

    func toggle() async { state == .listening ? stop() : await start() }

    func start() async {
        // .failed too, so a mic hiccup can be retried with the same button instead of leaving the app stuck.
        guard state != .listening, state != .loading, inference != nil else { return }
        ClipPlayer.shared.stop()
        let feeding = ProcessInfo.processInfo.arguments.contains("-feedfile")
        let allowed = feeding ? true : await AudioCapture.requestPermission()
        guard allowed else {
            state = .failed("Microphone access is off. Turn it on in Settings > Hark."); return
        }
        sessionID = UUID(); tracker.reset(); logged = [:]; clipBest = [:]; hearingNow = []; session = []
        sessionSpecies = []; startedAt = .now; patchAt = nil; agreed = []
        recentMaybes = [:]; maybes = []; manual = []; manualIndices = []; markers = []; lastMarker = [:]; notHere = []
        store.reset(); live.reset(); selection.unfreeze()
        let store = self.store, live = self.live
        audio.onSamples = { [weak self] s, db in
            store.append(s)
            live.append(s)
            Task { @MainActor in self?.levelDB = db }
        }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-feedfile"), i + 1 < args.count {
            audio.onFilesDone = { [weak self] in Task { @MainActor in try? await Task.sleep(for: .seconds(3)); self?.stop() } }
            audio.startFiles(args[i + 1].split(separator: ",").map { URL(fileURLWithPath: String($0)) })
        } else { do { try audio.start() } catch {
            state = .failed("Couldn't start the microphone: \(error.localizedDescription)"); return
        } }
        location.start(background: true)
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        state = .listening
        liveActivity.start()
        let rec = ListeningSession(id: sessionID, started: startedAt)
        modelContext?.insert(rec); sessionRecord = rec; lastTrackPoint = nil
        try? modelContext?.save()
        WidgetBridge.refresh(modelContext, listening: true, now: true)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hop)
                guard let self else { return }
                if self.stopAfterMinutes > 0, Date().timeIntervalSince(self.startedAt) > Double(self.stopAfterMinutes) * 60 {
                    self.stop(); return
                }
                self.updateSessionRecord()
                self.updateContext()          // also in Manual mode, so selections get season context
                await self.scoreLatest()
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        ClipPlayer.shared.stop()
        audio.stop(); location.stop()
        liveActivity.end()
        sessionRecord?.ended = .now; sessionRecord = nil
        try? modelContext?.save()
        WidgetBridge.refresh(modelContext, listening: false, now: true)
        UIApplication.shared.isIdleTimerDisabled = false
        if state == .listening { state = .ready }
        hearingNow = []; maybes = []
    }

    /// Extend the session's end time, and add a route point when we've moved more than 25 m.
    private func updateSessionRecord() {
        guard let rec = sessionRecord else { return }
        rec.ended = .now
        if Int(rec.ended.timeIntervalSince(rec.started)) % 10 == 0, modelContext?.hasChanges == true { try? modelContext?.save() }
        guard let loc = location.last, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else { return }
        if let last = lastTrackPoint, loc.distance(from: last) < 25 { return }
        rec.trackLat.append(loc.coordinate.latitude); rec.trackLon.append(loc.coordinate.longitude)
        lastTrackPoint = loc
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

    /// "Not it": this ID was wrong just now. Takes it off the screen and out of the log, and ignores the species
    /// for the rest of this session (the siren keeps going), without muting it for good. Noted for tuning. Undoable.
    func notIt(_ index: Int) {
        guard let l = label(index) else { return }
        notHere.insert(index)
        let occs = tracker.occurrences.filter { $0.index == index }
        var removed: [Detection] = [], keyed: [UUID: UUID] = [:]      // detection id -> occurrence id
        var best: [UUID: Float] = [:]
        for o in occs {
            if let d = logged.removeValue(forKey: o.id) { removed.append(d); keyed[d.id] = o.id }
            best[o.id] = clipBest.removeValue(forKey: o.id)
        }
        let hand = manual.filter { $0.scientific == l.scientific }
        removed += hand
        let handIDs = Set(hand.map(\.id))
        manual.removeAll { $0.scientific == l.scientific }
        let wasManual = manualIndices.remove(index) != nil
        let tag = UUID()
        if removed.isEmpty { WrongIDs.note(l, confidence: recentMaybes[index]?.best, source: "maybe", tag: tag) }
        removed.forEach { WrongIDs.note($0, tag: tag) }
        let undoFiles = modelContext.map { removeDetections(removed, in: $0) }
        tracker.drop(index)
        refreshSession()
        maybes.removeAll { $0.index == index }; recentMaybes[index] = nil
        markers.removeAll { $0.index == index }
        let wasSession = sessionSpecies.remove(index) != nil, wasAgreed = agreed.remove(index) != nil
        let session = sessionID

        UndoCenter.shared.offer("Not it: \(l.displayName)", undo: { [weak self] in
            guard let self else { return }
            WrongIDs.forget(tag)
            guard self.sessionID == session else {
                // a new session started since: just put the rows back in the log
                if let ctx = self.modelContext { undoFiles?.snapshots.forEach { _ = $0.restore(in: ctx) }; try? ctx.save() }
                return
            }
            self.notHere.remove(index)
            if let ctx = self.modelContext, let snaps = undoFiles?.snapshots {
                for snap in snaps {
                    let d = snap.restore(in: ctx)
                    if let o = keyed[snap.id] { self.logged[o] = d }
                    if handIDs.contains(snap.id) { self.manual.append(d) }
                }
                self.manual.sort { $0.firstHeard > $1.firstHeard }
                try? ctx.save()
                WidgetBridge.refresh(ctx, listening: self.state == .listening)
            }
            for (o, b) in best { self.clipBest[o] = b }
            if wasManual { self.manualIndices.insert(index) }
            if wasSession { self.sessionSpecies.insert(index) }
            if wasAgreed { self.agreed.insert(index) }
            self.tracker.restore(occs)
            self.refreshSession()
        }, commit: { undoFiles?.commit() })
    }
    private func refreshSession() {
        hearingNow = tracker.active(at: .now)
        session = tracker.occurrences.sorted { $0.firstHeard > $1.firstHeard }
    }
    /// From the Log: if it's from the session that's running, treat it like "Not it" there too.
    func notIt(_ d: Detection) {
        if state == .listening, d.sessionID == sessionID, let i = labels?.index(ofScientific: d.scientific),
           logged.values.contains(where: { $0.id == d.id }) || manual.contains(where: { $0.id == d.id }) {
            notIt(i); return
        }
        guard let ctx = modelContext else { return }
        let tag = UUID(), name = d.displayName
        WrongIDs.note(d, tag: tag)
        let (snaps, commit) = removeDetections([d], in: ctx)
        UndoCenter.shared.offer("Not it: \(name)", undo: {
            WrongIDs.forget(tag)
            snaps.forEach { _ = $0.restore(in: ctx) }
            try? ctx.save()
            WidgetBridge.refresh(ctx, listening: Listener.shared.state == .listening)
        }, commit: commit)
    }
    func commonName(_ scientific: String) -> String {
        labels?.labels.first { $0.scientific == scientific }?.common ?? scientific
    }

    /// Keep the location + season context current. Cheap to call every second: each source only recomputes when
    /// it needs to (GBIF: new ~150 km cell; geomodel: moved ~5 km or a new week; patch: moved 2 km; eBird: 3 h / 10 km).
    func updateContext() {
        guard labels != nil, let loc = location.last ?? location.lastKnown else { return }
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        var dirty = context == nil
        if let ranges {
            let c = ranges.cell(latitude: lat, longitude: lon)
            if localRange?.cell != c { localRange = ranges.local(latitude: lat, longitude: lon); dirty = true }
        }
        let week = GeoWeek.of(.now)
        let key = "\(Int((lat * 20).rounded())),\(Int((lon * 20).rounded())),\(week)"
        if let geo, key != geoKey, !geoRunning {
            geoKey = key; geoRunning = true
            Task {
                let g = await Task.detached(priority: .utility) { geo.expectations(latitude: lat, longitude: lon, week: week) }.value
                geoRunning = false
                if let g { geoExpectations = g; rebuildContext() }
            }
        }
        if patchAt == nil || loc.distance(from: patchAt!) > 2000 { patchAt = loc; rebuildPatch(); dirty = true }
        if ebird.needsRefresh(latitude: lat, longitude: lon) {
            Task { if await ebird.refreshIfNeeded(latitude: lat, longitude: lon) { rebuildContext() } }
        }
        if dirty { rebuildContext() }
    }

    /// Settings › Refresh now.
    func refreshEBird() async {
        guard let loc = location.last ?? location.lastKnown else { return }
        if await ebird.refreshIfNeeded(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, force: true) { rebuildContext() }
    }

    func rebuildContext() {
        guard let labels else { return }
        context = LocalContext(count: labels.count, range: localRange, geo: geoExpectations, patch: patch, ebird: ebird.indices(labels))
    }

    /// Your patch: species you've confirmed ("I saw it"), or logged on 3+ different days, within 10 km of here.
    func rebuildPatch() {
        guard let ctx = modelContext, let labels, let here = patchAt ?? location.last else { return }
        let all = (try? ctx.fetch(FetchDescriptor<Detection>())) ?? []
        var days: [String: Set<Int>] = [:], confirmed: Set<String> = []
        let cal = Calendar.current
        for d in all {
            guard let a = d.latitude, let b = d.longitude,
                  EBird.km(a, b, here.coordinate.latitude, here.coordinate.longitude) < 10 else { continue }
            days[d.scientific, default: []].insert(cal.ordinality(of: .day, in: .era, for: d.firstHeard) ?? 0)
            if d.confirmed { confirmed.insert(d.scientific) }
        }
        let names = confirmed.union(days.filter { $0.value.count >= 3 }.keys)
        patch = Set(names.compactMap { labels.index(ofScientific: $0) })
    }

    /// iNaturalist page for a label (its taxon id when known, else a search).
    func lookupURL(_ i: Int) -> URL? {
        guard let l = label(i), l.group.isSpecies else { return nil }
        if let id = l.inat { return URL(string: "https://www.inaturalist.org/taxa/\(id)") }
        return URL(string: "https://www.inaturalist.org/search?q=" + (l.scientific.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
    }

    /// Why an ID is flagged, for the "unusual" tag.
    func unusualReason(_ i: Int) -> String {
        if context?.status(i) == .outOfSeason {
            return "unusual for \(Date.now.formatted(.dateTime.month(.wide)))"
        }
        if context?.status(i) == .rare { return "rare here" }
        return "unusual here"
    }

    /// Score the newest 5 s. Runs about once a second, so each sound is seen in ~5 overlapping windows.
    private func scoreLatest() async {
        guard inference != nil, let labels, state == .listening, idMode == .auto else { return }
        guard store.count >= 32_000 * 2 else { return }   // wait for 2 s of audio
        guard Date() >= quietUntil else { return }         // playing a clip: the mic hears the speaker
        let w = store.latest(PerchClassifier.windowSamples)
        let t0 = Date()
        guard let triage = await identify(w) else { return }
        lastInferenceMs = Date().timeIntervalSince(t0) * 1000
        agreed.formUnion(triage.agreed)
        let result = WindowResult(time: .now, hits: triage.hits)
        if ProcessInfo.processInfo.arguments.contains("-autolisten") {
            NSLog("HARK-WINDOW %.0f ms: %@", lastInferenceMs, result.hits.map { "\(labels[$0.index].common) \(Int($0.confidence * 100))%" }.joined(separator: ", "))
        }
        for change in tracker.add(result) { log(change, labels) }
        if critters { placeMarkers(result.hits.map(\.index), labels) }
        hearingNow = tracker.active(at: .now)
        session = tracker.occurrences.sorted { $0.firstHeard > $1.firstHeard }
        updateMaybes(triage, at: result.time)
    }

    // MARK: Critters on the spectrogram

    /// A logged species pinned on the loudest spot of the window it was heard in.
    struct Marker: Identifiable, Equatable {
        let id = UUID(); let index: Int; let group: TaxonGroup; let name: String; let column: Int; let band: Int
    }
    var markers: [Marker] = []
    private var lastMarker: [Int: Date] = [:]
    var critters: Bool = UserDefaults.standard.object(forKey: "critters") as? Bool ?? true {
        didSet { UserDefaults.standard.set(critters, forKey: "critters") }
    }

    /// One pin per species every 6 s while it keeps calling; species heard together go on different bands.
    private func placeMarkers(_ hits: [Int], _ labels: LabelTable) {
        let logged = Set(tracker.occurrences.map(\.index)), now = Date()
        var used: [Int] = []
        for i in hits where logged.contains(i) && now.timeIntervalSince(lastMarker[i] ?? .distantPast) >= 6 {
            guard let p = live.peak(seconds: 4, avoiding: used) else { continue }
            used.append(p.band); lastMarker[i] = now
            markers.append(Marker(index: i, group: labels[i].group, name: labels[i].displayName, column: p.column, band: p.band))
        }
        if markers.count > 150 { markers.removeFirst(markers.count - 150) }
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
        maybes = recentMaybes.values.filter { showMaybes || $0.unusual }.sorted { ($0.unusual ? 1 : 0, $0.best) > ($1.unusual ? 1 : 0, $1.best) }.prefix(5).map { $0 }
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
            try? ctx.save()       // don't rely on autosave: iOS can kill a backgrounded walk at any time
            WidgetBridge.refresh(ctx, listening: true)
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

    // MARK: Touch-to-select

    var canSelect: Bool { store.count >= 32_000 }

    /// Freeze the last minute and show it where the live spectrogram was.
    func freezeForSelection() {
        let n = min(store.count, 32_000 * AudioStore.seconds)
        guard n >= 32_000, !selection.isFrozen else { return }
        selection.freeze(AudioSnapshot(samples: store.latest(n), end: .now), seconds: shownSeconds,
                         lagSamples: state == .listening ? live.lagSamples() : 0)
    }

    /// Score any stretch of audio with the chosen model(s): overlapping windows, best score per species.
    func analyze(_ samples: [Float]) async -> DetectionPolicy.Triage? { await identify(samples, topK: 15) }

    /// Log a species picked out of a selection, with the selection as its clip.
    func logSelection(_ index: Int, confidence: Float, samples: [Float], at: Date, confirmed: Bool) {
        guard let ctx = modelContext, let l = label(index) else { return }
        let loc = location.last?.coordinate
        let d = Detection(label: l, confidence: Double(confidence), at: at,
                          latitude: loc?.latitude, longitude: loc?.longitude, sessionID: sessionID, source: "selection")
        d.confirmed = confirmed
        markIfNew(d)
        ctx.insert(d)
        try? ctx.save()
        WidgetBridge.refresh(ctx, listening: state == .listening)
        manual.insert(d, at: 0); manualIndices.insert(index)
        if confirmed { rebuildPatch(); rebuildContext() }
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
        let c = (UUID(), d.displayName)
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
        liveActivity.newSpecies(l.displayName, symbol: l.group.symbol, count: sessionSpecies.count, firstEver: firstEver)
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
        try? ctx.save()
        WidgetBridge.refresh(ctx, listening: state == .listening)
        manual.insert(d, at: 0); manualIndices.insert(m.index)
        if confirmed { rebuildPatch(); rebuildContext() }
        let secs = min(15, Date().timeIntervalSince(m.firstSeen) + 5)
        let clip = store.latest(Int(secs * 32_000))
        Task { d.clipFile = await ClipStore.save(clip) }
        recentMaybes[m.index] = nil
        maybes.removeAll { $0.index == m.index }
    }
}
