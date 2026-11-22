import Foundation
import Security
import HarkCore

/// Optional: what birders reported on eBird within 25 km in the last 30 days, with the user's own free API key
/// (ebird.org/api/keygen). Those species are never flagged as unusual. Sends only a rounded (~1 km) location.
@MainActor
@Observable
final class EBird {
    struct Report: Codable { let speciesCode: String; let sciName: String; let comName: String }
    struct Cache: Codable { var lat: Double; var lon: Double; var fetched: Date; var reports: [Report] }

    private(set) var cache: Cache? = EBird.loadCache()
    private(set) var lastError: String?
    private(set) var fetching = false
    var hasKey: Bool { !(Keychain.get("ebirdKey") ?? "").isEmpty }

    var key: String {
        get { Keychain.get("ebirdKey") ?? "" }
        set {
            let k = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if k.isEmpty { Keychain.delete("ebirdKey"); cache = nil; Self.saveCache(nil) } else { Keychain.set(k, for: "ebirdKey") }
            lastError = nil
        }
    }

    /// Label indices reported nearby (matched by eBird code, then scientific name).
    func indices(_ labels: LabelTable) -> Set<Int> {
        guard let cache else { return [] }
        if byCode.isEmpty { for (i, l) in labels.labels.enumerated() { if let b = l.ebird { byCode[b] = i } } }
        return Set(cache.reports.compactMap { byCode[$0.speciesCode] ?? labels.index(ofScientific: $0.sciName) })
    }
    private var byCode: [String: Int] = [:]

    func needsRefresh(latitude: Double, longitude: Double) -> Bool {
        guard hasKey, !fetching, Date() >= retryAfter else { return false }
        guard let c = cache else { return true }
        return Date().timeIntervalSince(c.fetched) >= 3 * 3600 || Self.km(c.lat, c.lon, latitude, longitude) >= 10
    }
    private var retryAfter = Date.distantPast

    /// Refresh if the key is set and the cache is older than 3 hours or from more than 10 km away.
    func refreshIfNeeded(latitude: Double, longitude: Double, force: Bool = false) async -> Bool {
        guard hasKey, !fetching else { return false }
        if !force, let c = cache, Date().timeIntervalSince(c.fetched) < 3 * 3600,
           Self.km(c.lat, c.lon, latitude, longitude) < 10 { return false }
        fetching = true; defer { fetching = false }
        retryAfter = .now.addingTimeInterval(120)        // don't hammer eBird when offline or the key is bad
        let lat = (latitude * 100).rounded() / 100, lon = (longitude * 100).rounded() / 100
        var url = URLComponents(string: "https://api.ebird.org/v2/data/obs/geo/recent")!
        url.queryItems = [.init(name: "lat", value: "\(lat)"), .init(name: "lng", value: "\(lon)"),
                          .init(name: "dist", value: "25"), .init(name: "back", value: "30"), .init(name: "maxResults", value: "10000")]
        var req = URLRequest(url: url.url!, timeoutInterval: 20)
        req.setValue(key, forHTTPHeaderField: "X-eBirdApiToken")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                lastError = code == 401 || code == 403 ? "eBird didn't accept that key." : "eBird returned an error (\(code))."
                return false
            }
            let reports = try JSONDecoder().decode([Report].self, from: data)
            cache = Cache(lat: latitude, lon: longitude, fetched: .now, reports: reports)
            Self.saveCache(cache)
            lastError = nil
            return true
        } catch {
            lastError = "Couldn't reach eBird (\(error.localizedDescription)). Using the last list."
            return false
        }
    }

    static func km(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let dx = (d - b) * cos((a + c) / 2 * .pi / 180) * 111, dy = (c - a) * 111
        return (dx * dx + dy * dy).squareRoot()
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ebird.json")
    }
    private static func loadCache() -> Cache? { (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) } }
    private static func saveCache(_ c: Cache?) {
        guard let c else { try? FileManager.default.removeItem(at: cacheURL); return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(c).write(to: cacheURL)
    }
}

/// Minimal Keychain wrapper for the eBird key.
enum Keychain {
    private static func query(_ k: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.ducktyping.hark", kSecAttrAccount as String: k]
    }
    static func get(_ k: String) -> String? {
        var q = query(k); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ v: String, for k: String) {
        delete(k)
        var q = query(k); q[kSecValueData as String] = Data(v.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ k: String) { SecItemDelete(query(k) as CFDictionary) }
}
