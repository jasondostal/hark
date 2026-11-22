import Foundation

/// Two models, one scale. Hark's thresholds are in Perch's terms (softmax over 14,795 classes, so 30% is a solid
/// call); BirdNET+ gives independent sigmoids that run much higher. Calibrated on the bake-off (tools/bakeoff):
/// BirdNET+ 0.75 logs about as many extra species per clip as Perch 0.30, so 0.75 maps to 0.30, and each doubling of
/// the Perch threshold is two logit steps of BirdNET+.
public enum Fusion {
    public enum Model: String, Codable, CaseIterable, Sendable { case perch, birdnet, both }

    /// A BirdNET+ score on Hark's (Perch) scale.
    public static func perchEquivalent(_ b: Float) -> Float {
        let x = min(max(b, 1e-6), 1 - 1e-6)
        let logit = logf(x / (1 - x)), ref = logf(0.75 / 0.25)
        return min(0.99, 0.30 * expf((logit - ref) / 2))
    }

    /// "Agree, or one is sure", relative to a group threshold t (bake-off: at t = 0.30 this is Perch >= 0.25 and
    /// BirdNET+ >= 0.40, or Perch >= 0.70, or BirdNET+ >= 0.85; it found 6-7 more of every 100 calls than Perch
    /// alone at the same noise). `g` is BirdNET+ on Perch's scale.
    public static func agree(_ p: Float, _ g: Float, threshold t: Float) -> Bool { p >= 0.83 * t && g >= 0.47 * t }
    public static func sure(_ p: Float, _ g: Float, threshold t: Float) -> Bool { p >= 2.33 * t || g >= 1.37 * t }
}
