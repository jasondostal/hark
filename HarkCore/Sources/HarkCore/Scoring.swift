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
