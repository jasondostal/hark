import Foundation

/// One scored 5-second window, reduced to the classes above threshold.
public struct WindowResult: Sendable {
    public let time: Date
    public let hits: [(index: Int, confidence: Float)]
    public init(time: Date, hits: [(index: Int, confidence: Float)]) { self.time = time; self.hits = hits }

    /// Reduce softmax scores to hits at or above `threshold`, best first, at most `limit`.
    public init(time: Date, scores: [Float], threshold: Float, limit: Int = 5) {
        self.time = time
        hits = Scoring.topK(scores, limit).compactMap { scores[$0] >= threshold ? ($0, scores[$0]) : nil }
    }
}

/// What has been heard in a listening session. A species "occurrence" stays open while it keeps being heard;
/// a gap longer than `gap` starts a new occurrence (so a later return is logged again, not merged).
public struct DetectionTracker: Sendable {
    public struct Occurrence: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let index: Int
        public let firstHeard: Date
        public var lastHeard: Date
        public var bestConfidence: Float
        public var windows: Int
    }

    public var gap: TimeInterval
    /// A new species needs this many windows (seconds of live listening) within `confirmSpan` before it opens and is
    /// logged. One-window blips are most of the false IDs; tools/bakeoff/tune.py: 2 windows cut junk by about a
    /// quarter for 0-2% of real calls.
    public var confirmWindows: Int
    public var confirmSpan: TimeInterval
    public private(set) var occurrences: [Occurrence] = []   // in order first heard
    private var open: [Int: Int] = [:]                        // class index -> occurrences index
    private var pending: [Int: Occurrence] = [:]              // heard, not yet confirmed

    public init(gap: TimeInterval = 60, confirmWindows: Int = 2, confirmSpan: TimeInterval = 5) {
        self.gap = gap; self.confirmWindows = confirmWindows; self.confirmSpan = confirmSpan
    }

    public enum Change: Equatable, Sendable { case started(Occurrence), updated(Occurrence) }

    /// Fold one window in. Returns what changed so the caller can log it.
    @discardableResult
    public mutating func add(_ w: WindowResult) -> [Change] {
        var changes: [Change] = []
        for (idx, conf) in w.hits {
            if let k = open[idx], w.time.timeIntervalSince(occurrences[k].lastHeard) <= gap {
                occurrences[k].lastHeard = w.time
                occurrences[k].windows += 1
                occurrences[k].bestConfidence = max(occurrences[k].bestConfidence, conf)
                changes.append(.updated(occurrences[k]))
            } else {
                var o = pending[idx].flatMap { w.time.timeIntervalSince($0.lastHeard) <= confirmSpan ? $0 : nil }
                    ?? Occurrence(id: UUID(), index: idx, firstHeard: w.time, lastHeard: w.time, bestConfidence: conf, windows: 0)
                o.lastHeard = w.time; o.windows += 1; o.bestConfidence = max(o.bestConfidence, conf)
                if o.windows >= confirmWindows {
                    pending[idx] = nil
                    open[idx] = occurrences.count
                    occurrences.append(o)
                    changes.append(.started(o))
                } else {
                    pending[idx] = o
                }
            }
        }
        return changes
    }

    /// Occurrences heard within `window` seconds of `now`, most confident first.
    public func active(at now: Date, within window: TimeInterval = 8) -> [Occurrence] {
        occurrences.filter { now.timeIntervalSince($0.lastHeard) <= window }.sorted { $0.bestConfidence > $1.bestConfidence }
    }

    public mutating func reset() { occurrences = []; open = [:]; pending = [:] }

    /// "Not it": forget a species' occurrences this session (the caller stops it being scored again).
    public mutating func drop(_ index: Int) {
        occurrences.removeAll { $0.index == index }
        pending[index] = nil
        open = [:]
        for (k, o) in occurrences.enumerated() { open[o.index] = k }   // later occurrences of a species win, as in add()
    }

    /// Undo of `drop`: put occurrences back where they were (in order first heard).
    public mutating func restore(_ back: [Occurrence]) {
        let ids = Set(occurrences.map(\.id))
        occurrences += back.filter { !ids.contains($0.id) }
        occurrences.sort { $0.firstHeard < $1.firstHeard }
        open = [:]
        for (k, o) in occurrences.enumerated() { open[o.index] = k }
    }
}
