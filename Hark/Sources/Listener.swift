import Foundation
import Observation
import SwiftData
import UIKit
import HarkCore

/// Holds the newest 20 s of 32 kHz audio. Written from the audio thread, read by the scoring loop.
actor AudioStore {
    private var ring = RingBuffer(capacity: 32_000 * 20)
    func append(_ s: [Float]) { ring.append(s) }
    func latest(_ n: Int) -> [Float] { ring.latest(n) }
    var count: Int { ring.count }
    func reset() { ring.removeAll() }
}

/// Runs Perch off the main thread, one window at a time.
actor Inference {
    let classifier: PerchClassifier
    init(_ c: PerchClassifier) { classifier = c }
    func classify(_ w: [Float]) throws -> PerchClassifier.Output { try classifier.classify(w) }
}

struct CaptureResult: Identifiable {
    let id = UUID()
    let time: Date
    let hits: [(label: HarkCore.Label, confidence: Float)]
}

@MainActor
@Observable
final class Listener {
    enum State: Equatable { case loading, ready, listening, failed(String) }

    private(set) var state: State = .loading
    private(set) var labels: LabelTable?
    private(set) var hearingNow: [DetectionTracker.Occurrence] = []
    private(set) var session: [DetectionTracker.Occurrence] = []
    private(set) var spectrogram: [Float]?       // newest 5 s window, 500 x 128
    private(set) var levelDB: Float = -120
    private(set) var lastInferenceMs: Double = 0
    var capture: CaptureResult?

    // Settings (persisted)
    var threshold: Float = UserDefaults.standard.object(forKey: "threshold") as? Float ?? 0.3 {
        didSet { UserDefaults.standard.set(threshold, forKey: "threshold") }
    }
    var showSounds: Bool = UserDefaults.standard.object(forKey: "showSounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSounds, forKey: "showSounds") }
    }

    private var inference: Inference?
    private let store = AudioStore()
    private let audio = AudioCapture()
    private let location = LocationProvider()
    private var tracker = DetectionTracker(gap: 60)
    private var loop: Task<Void, Never>?
    private var sessionID = UUID()
    private var logged: [UUID: Detection] = [:]   // occurrence id -> its log row
    var modelContext: ModelContext?

    static let hop: Duration = .seconds(1)

    func loadModel() async {
        guard inference == nil else { return }
        do {
            guard let modelURL = Bundle.main.url(forResource: "Perch", withExtension: "mlmodelc"),
                  let labelsURL = Bundle.main.url(forResource: "labels", withExtension: "json") else {
                state = .failed("Model files missing from the app bundle"); return
            }
            let (clf, table) = try await Task.detached(priority: .userInitiated) {
                let c = try PerchClassifier(url: modelURL, computeUnits: .all)
                _ = try c.classify([Float](repeating: 0, count: PerchClassifier.windowSamples))   // warm up / ANE compile
                return (c, try LabelTable(contentsOf: labelsURL))
            }.value
            inference = Inference(clf); labels = table
            state = .ready
        } catch {
            state = .failed("Couldn't load Perch: \(error.localizedDescription)")
        }
    }

    func label(_ i: Int) -> HarkCore.Label? { labels.map { $0[i] } }

    func toggle() async { state == .listening ? stop() : await start() }

    func start() async {
        guard state == .ready, inference != nil else { return }
        guard await AudioCapture.requestPermission() else {
            state = .failed("Microphone access is off. Turn it on in Settings > Hark."); return
        }
        sessionID = UUID(); tracker.reset(); logged = [:]; hearingNow = []; session = []
        await store.reset()
        let store = self.store
        audio.onSamples = { [weak self] s, db in
            Task { await store.append(s) }
            Task { @MainActor in self?.levelDB = db }
        }
        do { try audio.start() } catch {
            state = .failed("Couldn't start the microphone: \(error.localizedDescription)"); return
        }
        location.start()
        UIApplication.shared.isIdleTimerDisabled = true
        state = .listening
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hop)
                await self?.scoreLatest()
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        audio.stop(); location.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if state == .listening { state = .ready }
        hearingNow = []
    }

    /// Score the newest 5 s. Runs about once a second, so each sound is seen in ~5 overlapping windows.
    private func scoreLatest() async {
        guard let inference, let labels, state == .listening else { return }
        guard await store.count >= 32_000 * 2 else { return }   // wait for 2 s of audio
        let w = await store.latest(PerchClassifier.windowSamples)
        let t0 = Date()
        guard let out = try? await inference.classify(w) else { return }
        lastInferenceMs = Date().timeIntervalSince(t0) * 1000
        spectrogram = out.spectrogram
        let scores = Scoring.softmax(out.logits)
        var result = WindowResult(time: .now, scores: scores, threshold: threshold)
        if !showSounds { result = WindowResult(time: result.time, hits: result.hits.filter { labels[$0.index].group.isSpecies }) }
        for change in tracker.add(result) { log(change, labels) }
        hearingNow = tracker.active(at: .now)
        session = tracker.occurrences.sorted { $0.firstHeard > $1.firstHeard }
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
            ctx.insert(d); logged[o.id] = d
        case .updated(let o):
            guard let d = logged[o.id] else { return }
            d.lastHeard = o.lastHeard; d.windows = o.windows; d.confidence = Double(o.bestConfidence)
        }
    }

    func detection(for o: DetectionTracker.Occurrence) -> Detection? { logged[o.id] }

    /// "What was that?": score the last 15 s (5 overlapping windows), keep the best score per class.
    func captureLast15s() async {
        guard let inference, let labels, state == .listening else { return }
        let n = PerchClassifier.windowSamples
        let audio = await store.latest(32_000 * 15)
        var best = [Float](repeating: 0, count: labels.count)
        for start in stride(from: 0, through: audio.count - n, by: 40_000) {   // every 1.25 s
            guard let out = try? await inference.classify(Array(audio[start..<(start + n)])) else { continue }
            let p = Scoring.softmax(out.logits)
            for i in p.indices where p[i] > best[i] { best[i] = p[i] }
        }
        let floor = min(threshold, 0.15)
        let hits = Scoring.topK(best, 8).filter { best[$0] >= floor }.map { (labels[$0], best[$0]) }
        capture = CaptureResult(time: .now, hits: hits)
    }

    /// Log a species from the capture sheet (optionally already confirmed).
    func logFromCapture(_ l: HarkCore.Label, confidence: Float, confirmed: Bool) {
        guard let ctx = modelContext else { return }
        let loc = location.last?.coordinate
        let d = Detection(label: l, confidence: Double(confidence), at: capture?.time ?? .now,
                          latitude: loc?.latitude, longitude: loc?.longitude, sessionID: sessionID, source: "capture")
        d.confirmed = confirmed
        ctx.insert(d)
    }
}
