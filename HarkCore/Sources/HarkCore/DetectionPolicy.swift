import Foundation

/// Per-group listening settings.
public struct GroupSetting: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var threshold: Float
    public init(enabled: Bool = true, threshold: Float) { self.enabled = enabled; self.threshold = threshold }
}

/// What to do with a confident hit on a species that's never been recorded near you.
public enum RangeMode: String, Codable, CaseIterable, Sendable {
    case off, flag, hide
}

/// The groups that get their own switch and threshold. Fish, "other" and unknown share one.
public enum ListenGroup: String, Codable, CaseIterable, Sendable {
    case bird, amphibian, insect, mammal, reptile, other, sound

    public init(_ g: TaxonGroup) {
        switch g {
        case .bird: self = .bird
        case .amphibian: self = .amphibian
        case .insect: self = .insect
        case .mammal: self = .mammal
        case .reptile: self = .reptile
        case .sound: self = .sound
        case .fish, .other, .unknown: self = .other
        }
    }

    public var title: String {
        switch self {
        case .bird: "Birds"
        case .amphibian: "Frogs & toads"
        case .insect: "Insects"
        case .mammal: "Mammals"
        case .reptile: "Reptiles"
        case .other: "Other animals"
        case .sound: "Non-animal sounds"
        }
    }

    public var symbol: String {
        switch self {
        case .bird: TaxonGroup.bird.symbol
        case .amphibian: TaxonGroup.amphibian.symbol
        case .insect: TaxonGroup.insect.symbol
        case .mammal: TaxonGroup.mammal.symbol
        case .reptile: TaxonGroup.reptile.symbol
        case .other: TaxonGroup.other.symbol
        case .sound: TaxonGroup.sound.symbol
        }
    }

    /// Insects and the catch-all start stricter: that's where Perch is least reliable.
    public var defaultSetting: GroupSetting {
        switch self {
        case .insect, .other: GroupSetting(threshold: 0.4)
        default: GroupSetting(threshold: 0.3)
        }
    }
}

/// Sorts one window's scores into what to show and log.
public struct DetectionPolicy: Codable, Equatable, Sendable {
    public var groups: [ListenGroup: GroupSetting]
    public var rangeMode: RangeMode

    public init(groups: [ListenGroup: GroupSetting] = [:], rangeMode: RangeMode = .flag) {
        self.groups = groups; self.rangeMode = rangeMode
    }

    public func setting(_ g: ListenGroup) -> GroupSetting { groups[g] ?? g.defaultSetting }
    public mutating func set(_ g: ListenGroup, _ s: GroupSetting) { groups[g] = s }

    /// Under the threshold but above this, a species shows as a "maybe". Below half the threshold it's mostly noise.
    public func maybeFloor(_ g: ListenGroup) -> Float { max(0.08, setting(g).threshold * 0.5) }

    public struct Triage: Sendable {
        /// confident and plausible here: shown and logged
        public var hits: [(index: Int, confidence: Float)] = []
        /// plausible but under the threshold: shown faintly, logged only by hand
        public var maybes: [(index: Int, confidence: Float)] = []
        /// confident but never recorded near you (rangeMode .flag): shown flagged, logged only by hand
        public var unusual: [(index: Int, confidence: Float)] = []
    }

    public func triage(scores: [Float], labels: LabelTable, range: LocalRange?, muted: Set<Int> = [], topK: Int = 12) -> Triage {
        var t = Triage()
        for i in Scoring.topK(scores, topK) {
            let label = labels[i]
            let g = ListenGroup(label.group)
            let s = setting(g)
            guard s.enabled, !muted.contains(i) else { continue }
            let p = scores[i]
            let status: RangeMap.Status = (rangeMode == .off || !label.group.isSpecies) ? .unknown : (range?.status(i) ?? .unknown)
            if p >= s.threshold {
                if status == .outOfRange {
                    if rangeMode == .flag { t.unusual.append((i, p)) }
                } else {
                    t.hits.append((i, p))
                }
            } else if p >= maybeFloor(g), label.group.isSpecies, status != .outOfRange {
                t.maybes.append((i, p))
            }
        }
        return t
    }
}
