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
    public var defaultSetting: GroupSetting { GroupSetting(threshold: Preset.balanced.threshold(self)) }
}

/// One-tap sensitivity presets. Perch's scores are a softmax over 14,795 classes, so they run far lower than
/// BirdNET's per-species confidences: on 48 backyard clips BirdNET-Go logged at 0.80-1.00, Perch's median was 0.70;
/// a 0.30 bar logged 75% of them, 0.50 69%, 0.85 only 25%.
public enum Preset: String, CaseIterable, Sendable {
    case sensitive, balanced, strict

    public var title: String { rawValue.capitalized }
    /// Displayed (BirdNET-style) logging bar for birds, frogs, mammals, reptiles and sounds; insects and "other",
    /// where the models are least reliable, sit higher.
    public var shown: Float { switch self { case .sensitive: 0.70; case .balanced: 0.85; case .strict: 0.92 } }
    public var shownInsect: Float { switch self { case .sensitive: 0.80; case .balanced: 0.90; case .strict: 0.95 } }
    public func threshold(_ g: ListenGroup) -> Float {
        Fusion.fromDisplay(g == .insect || g == .other ? shownInsect : shown)
    }
    /// The insect / "other" bar that goes with a main bar anywhere on the slider: a line through the three presets
    /// (70 -> 80, 85 -> 90, 92 -> 95), so the slider at a preset's value is exactly that preset.
    public static func shownInsect(for shown: Float) -> Float {
        let pts: [(Float, Float)] = [(0.50, 0.65), (0.70, 0.80), (0.85, 0.90), (0.92, 0.95), (0.98, 0.985)]
        if shown <= pts[0].0 { return pts[0].1 }
        for (a, b) in zip(pts, pts.dropFirst()) where shown <= b.0 {
            return a.1 + (b.1 - a.1) * (shown - a.0) / (b.0 - a.0)
        }
        return pts[pts.count - 1].1
    }
    /// Pre-1.0 presets (Perch scale), to move saved settings onto the new ones.
    public var legacyBase: Float { switch self { case .sensitive: 0.15; case .balanced: 0.30; case .strict: 0.50 } }
    public var blurb: String {
        switch self {
        case .sensitive: "Catches faint and distant calls, with more wrong guesses. Check before you trust them."
        case .balanced: "Logs confident IDs, like BirdNET at 85%. A good default."
        case .strict: "Only the surest IDs. Misses some real calls, rarely wrong."
        }
    }
}

/// How hard Hark leans on "there are people or music in this window" before it trusts an animal ID.
/// The value is the summed human-sound score that trips the guard (Fusion.humanSoundClasses): lower trips sooner.
public enum HumanGuard: String, Codable, CaseIterable, Sendable {
    case off, light, standard, strong
    public var gate: Float? {
        switch self { case .off: nil; case .light: 0.40; case .standard: Fusion.humanGate; case .strong: 0.10 }
    }
    public var title: String { rawValue.capitalized }
}

/// Sorts one window's scores into what to show and log.
public struct DetectionPolicy: Codable, Equatable, Sendable {
    public var groups: [ListenGroup: GroupSetting]
    public var rangeMode: RangeMode
    /// Voices & music guard (1.0 shipped with .standard, fixed).
    public var humanGuard: HumanGuard
    /// Count breathing, coughs and sneezes toward the guard too (Fusion.bodySoundClasses).
    public var guardBodySounds: Bool

    public init(groups: [ListenGroup: GroupSetting] = [:], rangeMode: RangeMode = .flag,
                humanGuard: HumanGuard = .standard, guardBodySounds: Bool = false) {
        self.groups = groups; self.rangeMode = rangeMode
        self.humanGuard = humanGuard; self.guardBodySounds = guardBodySounds
    }

    /// Settings saved by 1.0 have no guard keys: they keep what 1.0 did.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = try c.decodeIfPresent([ListenGroup: GroupSetting].self, forKey: .groups) ?? [:]
        rangeMode = try c.decodeIfPresent(RangeMode.self, forKey: .rangeMode) ?? .flag
        humanGuard = try c.decodeIfPresent(HumanGuard.self, forKey: .humanGuard) ?? .standard
        guardBodySounds = try c.decodeIfPresent(Bool.self, forKey: .guardBodySounds) ?? false
    }

    public func setting(_ g: ListenGroup) -> GroupSetting { groups[g] ?? g.defaultSetting }

    /// Settings saved before the BirdNET-style scale: an old preset becomes the same-named new one.
    public mutating func migrateLegacyPresets() {
        for p in Preset.allCases where ListenGroup.allCases.allSatisfy({ g in
            abs(setting(g).threshold - ((g == .insect || g == .other) ? p.legacyBase + 0.10 : p.legacyBase)) < 1e-4 }) {
            apply(p); return
        }
    }

    /// Set every group's threshold from a preset (on/off switches are kept).
    public mutating func apply(_ p: Preset) {
        for g in ListenGroup.allCases { groups[g] = GroupSetting(enabled: setting(g).enabled, threshold: p.threshold(g)) }
    }
    /// The preset these thresholds match, or nil if they've been fine-tuned ("Custom").
    public var preset: Preset? {
        Preset.allCases.first { p in ListenGroup.allCases.allSatisfy { abs(setting($0).threshold - p.threshold($0)) < 0.001 } }
    }
    public mutating func set(_ g: ListenGroup, _ s: GroupSetting) { groups[g] = s }

    /// One slider for every group: `shown` is the displayed logging bar for birds, frogs, mammals, reptiles and
    /// sounds; insects and "other" follow it on their stricter line (Preset.shownInsect(for:)).
    public mutating func apply(shown: Float) {
        let insect = Preset.shownInsect(for: shown)
        for g in ListenGroup.allCases {
            groups[g] = GroupSetting(enabled: setting(g).enabled, threshold: Fusion.fromDisplay(g == .insect || g == .other ? insect : shown))
        }
    }
    /// The main (bird) bar as displayed, for that slider.
    public var shown: Float { Fusion.display(setting(.bird).threshold) }

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
        /// The voices & music guard tripped on this window: only 'sure' animal IDs were let through.
        public var guarded = false
    }

    /// `scores` are on Hark's (Perch) scale, one per label. With `second` (BirdNET+ on the same scale, Both mode), a
    /// species is a hit when the two agree or either is sure (Fusion), and its confidence is the stronger of the two.
    /// `humanSound`: Perch's summed music / speech score for the window (Fusion.humanSoundClasses). At or above
    /// the guard's gate (`humanGuard`) only 'sure' animal IDs count and no animal maybes are shown.
    public func triage(scores: [Float], second: [Float]? = nil, labels: LabelTable, context: LocalContext?,
                       muted: Set<Int> = [], topK: Int = 12, humanSound: Float = 0) -> Triage {
        var t = Triage()
        let gated = humanGuard.gate.map { humanSound >= $0 } ?? false
        t.guarded = gated
        var candidates = Scoring.topK(scores, topK)
        if let second { candidates = Array(Set(candidates).union(Scoring.topK(second, topK))).sorted() }
        for i in candidates where i < labels.count {
            let label = labels[i]
            let g = ListenGroup(label.group)
            let s = setting(g)
            guard s.enabled, !muted.contains(i) else { continue }
            var p = i < scores.count ? scores[i] : 0
            if gated && label.group.isSpecies {
                let q = second.map { i < $0.count ? $0[i] : 0 } ?? 0
                guard Fusion.sure(p, q, threshold: s.threshold) else { continue }
            }
            if let second {
                let q = i < second.count ? second[i] : 0
                let both = Fusion.agree(p, q, threshold: s.threshold)
                let hit = both || Fusion.sure(p, q, threshold: s.threshold)
                // A hit is reported at or above the threshold; a non-hit stays below it (at most a maybe).
                p = hit ? max(max(p, q), s.threshold) : min(max(p, q), s.threshold * 0.999)
                if hit && both { t.agreed.insert(i) }
            }
            let status: LocalContext.Status = (rangeMode == .off || !label.group.isSpecies) ? .unknown : (context?.status(i) ?? .unknown)
            let unlikely = status == .outOfRange || status == .outOfSeason || status == .rare
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
