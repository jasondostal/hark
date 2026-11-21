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
    public private(set) var occurrences: [Occurrence] = []   // in order first heard
    private var open: [Int: Int] = [:]                        // class index -> occurrences index

    public init(gap: TimeInterval = 60) { self.gap = gap }

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
                let o = Occurrence(id: UUID(), index: idx, firstHeard: w.time, lastHeard: w.time, bestConfidence: conf, windows: 1)
                open[idx] = occurrences.count
                occurrences.append(o)
                changes.append(.started(o))
            }
        }
        return changes
    }

    /// Occurrences heard within `window` seconds of `now`, most confident first.
    public func active(at now: Date, within window: TimeInterval = 8) -> [Occurrence] {
        occurrences.filter { now.timeIntervalSince($0.lastHeard) <= window }.sorted { $0.bestConfidence > $1.bestConfidence }
    }

    public mutating func reset() { occurrences = []; open = [:] }
}
