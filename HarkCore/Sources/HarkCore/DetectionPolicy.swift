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

/// One-tap sensitivity presets. Perch's scores are a softmax over 14,795 classes, so they run far lower than
/// BirdNET's per-species confidences: on 48 backyard clips BirdNET-Go logged at 0.80-1.00, Perch's median was 0.70;
/// a 0.30 bar logged 75% of them, 0.50 69%, 0.85 only 25%.
public enum Preset: String, CaseIterable, Sendable {
    case sensitive, balanced, strict

    public var title: String { rawValue.capitalized }
    /// Threshold for birds, frogs, mammals, reptiles and sounds; insects and "other" sit 0.10 higher.
    public var base: Float { switch self { case .sensitive: 0.15; case .balanced: 0.30; case .strict: 0.50 } }
    public func threshold(_ g: ListenGroup) -> Float { g == .insect || g == .other ? base + 0.10 : base }
    public var blurb: String {
        switch self {
        case .sensitive: "Catches faint and distant calls. More wrong guesses: check before you trust them."
        case .balanced: "A good default. Logs most clear calls; quieter ones show as maybes."
        case .strict: "Only logs Perch's surest IDs. Misses some real ones, rarely wrong."
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

    /// Set every group's threshold from a preset (on/off switches are kept).
    public mutating func apply(_ p: Preset) {
        for g in ListenGroup.allCases { groups[g] = GroupSetting(enabled: setting(g).enabled, threshold: p.threshold(g)) }
    }
    /// The preset these thresholds match, or nil if they've been fine-tuned ("Custom").
    public var preset: Preset? {
        Preset.allCases.first { p in ListenGroup.allCases.allSatisfy { abs(setting($0).threshold - p.threshold($0)) < 0.001 } }
    }
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
        /// Both models: hits both models backed (the rest were one model being sure).
        public var agreed: Set<Int> = []
    }

    /// `scores` are on Hark's (Perch) scale, one per label. With `second` (BirdNET+ on the same scale, Both mode), a
    /// species is a hit when the two agree or either is sure (Fusion), and its confidence is the stronger of the two.
    public func triage(scores: [Float], second: [Float]? = nil, labels: LabelTable, context: LocalContext?,
                       muted: Set<Int> = [], topK: Int = 12) -> Triage {
        var t = Triage()
        var candidates = Scoring.topK(scores, topK)
        if let second { candidates = Array(Set(candidates).union(Scoring.topK(second, topK))).sorted() }
        for i in candidates where i < labels.count {
            let label = labels[i]
            let g = ListenGroup(label.group)
            let s = setting(g)
            guard s.enabled, !muted.contains(i) else { continue }
            var p = i < scores.count ? scores[i] : 0
            if let second {
                let q = i < second.count ? second[i] : 0
                let both = Fusion.agree(p, q, threshold: s.threshold)
                let hit = both || Fusion.sure(p, q, threshold: s.threshold)
                // A hit is reported at or above the threshold; a non-hit stays below it (at most a maybe).
                p = hit ? max(max(p, q), s.threshold) : min(max(p, q), s.threshold * 0.999)
                if hit && both { t.agreed.insert(i) }
            }
            let status: LocalContext.Status = (rangeMode == .off || !label.group.isSpecies) ? .unknown : (context?.status(i) ?? .unknown)
            let unlikely = status == .outOfRange || status == .outOfSeason
            if p >= s.threshold {
                if unlikely {
                    if rangeMode == .flag { t.unusual.append((i, p)) }
                } else {
                    t.hits.append((i, p))
                }
            } else if p >= maybeFloor(g), label.group.isSpecies, !unlikely {
                t.maybes.append((i, p))
            }
        }
        return t
    }
}
