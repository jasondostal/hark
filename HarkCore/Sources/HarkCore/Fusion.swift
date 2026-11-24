import Foundation

/// Two models, one scale. Hark's thresholds are in Perch's terms (softmax over 14,795 classes, so 30% is a solid
/// call); BirdNET+ gives independent sigmoids that run much higher. Calibrated on the bake-off (tools/bakeoff):
/// BirdNET+ 0.75 logs about as many extra species per clip as Perch 0.30, so 0.75 maps to 0.30, and each doubling of
/// the Perch threshold is two logit steps of BirdNET+.
public enum Fusion {
    public enum Model: String, Codable, CaseIterable, Sendable { case perch, birdnet, both }

    /// What people see: a Perch-scale score as the BirdNET-style percentage every other app shows (0.30 -> 75%,
    /// 0.41 -> 85%, 0.50 -> 89%, 0.70 -> 94%). Logic stays on Perch's scale; only the display converts.
    public static func display(_ p: Float) -> Float {
        let logit = logf(3) + 2 * logf(max(p, 1e-6) / 0.30)
        return 1 / (1 + expf(-logit))
    }
    /// The Perch-scale score that displays as `d` (for sliders and presets written in displayed percentages).
    public static func fromDisplay(_ d: Float) -> Float {
        let x = min(max(d, 0.01), 0.995)
        return min(0.99, 0.30 * expf((logf(x / (1 - x)) - logf(3)) / 2))
    }

    /// Music, singing, speech and other human sounds Perch recognises. When they fill a window (summed score >=
    /// humanGate), a song on the TV shouldn't become a bird: only 'sure' animal IDs count in that window.
    public static let humanSoundClasses = ["Acoustic_guitar", "Bass_guitar", "Bowed_string_instrument", "Brass_instrument",
        "Child_speech_and_kid_speaking", "Conversation", "Crowd", "Electric_guitar", "Female_singing",
        "Female_speech_and_woman_speaking", "Guitar", "Homo sapiens", "Human_voice", "Keyboard_(musical)", "Laughter", "Male_singing",
        "Male_speech_and_man_speaking", "Music", "Musical_instrument", "Piano", "Plucked_string_instrument", "Singing",
        "Speech", "Speech_synthesizer", "Telephone", "Wind_instrument_and_woodwind_instrument"]
    public static let humanGate: Float = 0.20
    /// Sounds a person makes right at the phone. Optional extras for the guard (DetectionPolicy.guardBodySounds):
    /// off by default, since 1.0 never counted them. Footsteps are left out on purpose: a walk would trip it all day.
    public static let bodySoundClasses = ["Breathing", "Cough", "Sneeze", "Sigh", "Gasp", "Whispering",
        "Burping_and_eructation", "Chewing_and_mastication"]

    /// Perch hears pets mostly as AudioSet sound classes: on 40 ESC-50 dog barks "Domestic Dog" itself never passed
    /// 0.18 while "Dog" + "Bark" held most of the score (Perch alone logged 0/40). Their score is moved onto the
    /// species: Perch alone then logs 25/40 dogs and 16/40 cats, Both 34/40 and 32/40 (from 29 and 29), with no new
    /// false IDs on the other ESC-50 animals or the 227 wildlife clips (tools/bakeoff/pets.py).
    public static let soundSynonyms: [String: [String]] = [
        "Canis familiaris": ["Dog", "Bark", "Growling"],
        "Felis catus": ["Cat", "Meow", "Purr"],
    ]

    /// Resolve `soundSynonyms` to label indices once per label table.
    public static func synonymIndices(_ labels: LabelTable) -> [(species: Int, sounds: [Int])] {
        soundSynonyms.compactMap { sp, sounds in
            labels.index(ofScientific: sp).map { ($0, sounds.compactMap { labels.index(ofScientific: $0) }) }
        }
    }

    /// Move each synonym sound class's Perch score onto its species (softmax mass, so the sum is still a probability).
    public static func poolSynonyms(_ p: inout [Float], _ groups: [(species: Int, sounds: [Int])]) {
        for (sp, sounds) in groups where sp < p.count {
            for j in sounds where j < p.count { p[sp] += p[j]; p[j] = 0 }
            p[sp] = min(p[sp], 1)
        }
    }

    /// A BirdNET+ score on Hark's (Perch) scale.
    public static func perchEquivalent(_ b: Float) -> Float {
        let x = min(max(b, 1e-6), 1 - 1e-6)
        let logit = logf(x / (1 - x)), ref = logf(0.75 / 0.25)
        return min(0.99, 0.30 * expf((logit - ref) / 2))
    }

    /// "Agree, or one is sure". The agreement bar scales with the group threshold t (at t = 0.30: Perch >= 0.25 and
    /// BirdNET+ >= 0.40). The "sure" bars are fixed (Perch 0.70, BirdNET+ about 0.85 = 0.41 on Perch's scale) or the
    /// threshold if higher: scaling them too punished Strict (distant birds Perch is sure of but BirdNET+ barely hears)
    /// and made Sensitive noisy. tools/bakeoff/tune.py, live replay with 2-window confirmation: Balanced finds 92% /
    /// 83% (iNat / yard) vs Perch alone 86% / 75% at the same noise. `g` is BirdNET+ on Perch's scale.
    public static func agree(_ p: Float, _ g: Float, threshold t: Float) -> Bool { p >= 0.83 * t && g >= 0.47 * t }
    public static func sure(_ p: Float, _ g: Float, threshold t: Float) -> Bool { p >= max(0.70, t) || g >= max(0.41, 1.03 * t) }
}
