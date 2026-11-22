import Foundation
import HarkCore

/// IDs people said were wrong ("Not it"), kept on the phone for tuning: species, score, how it was logged, when.
/// No locations. Newest last, capped.
enum WrongIDs {
    private static let key = "wrongIDs"
    static var all: [[String: Any]] { UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? [] }

    @MainActor static func note(_ d: Detection) {
        add(["scientific": d.scientific, "confidence": d.confidence, "windows": d.windows, "source": d.source,
             "heard": d.firstHeard.timeIntervalSince1970, "said": Date.now.timeIntervalSince1970])
    }
    static func note(_ l: HarkCore.Label, confidence: Float?, source: String) {
        add(["scientific": l.scientific, "confidence": Double(confidence ?? 0), "windows": 0, "source": source,
             "heard": Date.now.timeIntervalSince1970, "said": Date.now.timeIntervalSince1970])
    }
    private static func add(_ e: [String: Any]) {
        var a = all; a.append(e)
        UserDefaults.standard.set(Array(a.suffix(500)), forKey: key)
    }
}
