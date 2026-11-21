import Foundation

/// Perch logits are uncalibrated. Like birdnet-go, turn them into confidences with a softmax over the model's classes.
/// For a regional slice, `restLogit` stands in for the excluded classes so scores stay on the full model's scale
/// (birdnet-go perchSoftmaxWithRest). The full model needs no rest term.
public enum Scoring {
    public static func softmax(_ logits: [Float], restLogit: Float? = nil) -> [Float] {
        guard var m = logits.max() else { return [] }
        if let r = restLogit { m = max(m, r) }
        var e = logits.map { Foundation.exp(Double($0 - m)) }
        var sum = e.reduce(0, +)
        if let r = restLogit { sum += Foundation.exp(Double(r - m)) }
        for i in e.indices { e[i] /= sum }
        return e.map { Float($0) }
    }

    /// Indices of the `k` largest values, largest first.
    public static func topK(_ v: [Float], _ k: Int) -> [Int] {
        guard k > 0, !v.isEmpty else { return [] }
        if k == 1 { return [v.indices.max(by: { v[$0] < v[$1] })!] }
        var best: [(Int, Float)] = []
        best.reserveCapacity(k + 1)
        for (i, x) in v.enumerated() where best.count < k || x > best[best.count - 1].1 {
            let pos = best.firstIndex(where: { $0.1 < x }) ?? best.count
            best.insert((i, x), at: pos)
            if best.count > k { best.removeLast() }
        }
        return best.map(\.0)
    }
}

/// How a stretch of audio of any length is cut into Perch's 5 s windows.
public enum Windowing {
    /// Window start offsets (in samples, relative to the stretch). A stretch shorter than one window gives one
    /// negative start: the stretch is centered and the window is zero-padded on both sides. Longer stretches get
    /// windows every `hop`, with the last one aligned to the end so nothing at the end is missed.
    public static func starts(length: Int, window: Int = 160_000, hop: Int = 80_000) -> [Int] {
        guard length > 0 else { return [] }
        if length <= window { return [-(window - length) / 2] }
        var s = Array(stride(from: 0, through: length - window, by: hop))
        if s.last != length - window { s.append(length - window) }
        return s
    }

    /// The window at `start`, zero-filled wherever it falls outside `samples`.
    public static func window(_ samples: [Float], start: Int, window: Int = 160_000) -> [Float] {
        var w = [Float](repeating: 0, count: window)
        let lo = max(start, 0), hi = min(start + window, samples.count)
        if lo < hi { w.replaceSubrange((lo - start)..<(hi - start), with: samples[lo..<hi]) }
        return w
    }

    /// Element-wise max of per-window score vectors: a species counts if any window heard it.
    public static func maxPool(_ rows: [[Float]]) -> [Float] {
        guard var best = rows.first else { return [] }
        for r in rows.dropFirst() { for i in best.indices where r[i] > best[i] { best[i] = r[i] } }
        return best
    }
}
