import Foundation

public enum TaxonGroup: String, Codable, CaseIterable, Sendable {
    case bird, amphibian, mammal, insect, reptile, fish, sound, other, unknown

    /// SF Symbol for the group.
    public var symbol: String {
        switch self {
        case .bird: "bird"
        case .amphibian: "drop"
        case .mammal: "pawprint"
        case .insect: "ant"
        case .reptile: "lizard"
        case .fish: "fish"
        case .sound: "waveform"
        case .other, .unknown: "questionmark.circle"
        }
    }
    public var isSpecies: Bool { self != .sound }
}

public struct Label: Codable, Hashable, Sendable {
    public let scientific: String
    public let common: String
    public let group: TaxonGroup
    /// A picture for the kind of animal or sound (owl, duck, frog, cricket, car...), from tools/make_labels.py.
    public let emoji: String?
    /// iNaturalist taxon id, for "look it up" links.
    public let inat: Int?
    enum CodingKeys: String, CodingKey { case scientific = "s", common = "c", group = "g", emoji = "e", inat = "i" }
    public init(scientific: String, common: String, group: TaxonGroup, emoji: String? = nil, inat: Int? = nil) {
        self.scientific = scientific; self.common = common; self.group = group; self.emoji = emoji; self.inat = inat
    }
    public var icon: String { emoji ?? "❔" }
}

/// Class index -> label, in the model's output order (built by tools/make_labels.py).
public struct LabelTable: Sendable {
    public let labels: [Label]
    public init(labels: [Label]) { self.labels = labels; _byScientific.set(Self.index(labels)) }
    public init(contentsOf url: URL) throws {
        labels = try JSONDecoder().decode([Label].self, from: Data(contentsOf: url))
        _byScientific.set(Self.index(labels))
    }
    private static func index(_ l: [Label]) -> [String: Int] {
        Dictionary(l.enumerated().map { ($1.scientific, $0) }, uniquingKeysWith: { a, _ in a })
    }
    public subscript(i: Int) -> Label { labels[i] }
    public var count: Int { labels.count }
    public func index(ofScientific s: String) -> Int? { labels.firstIndex { $0.scientific == s } }
    /// Label by scientific name (built on first use).
    public func label(scientific s: String) -> Label? { byScientific[s].map { labels[$0] } }
    private var byScientific: [String: Int] { _byScientific.value }
    private let _byScientific = Lazy<[String: Int]>()
}

/// Write-once holder so LabelTable stays a Sendable value type.
final class Lazy<T: Sendable>: @unchecked Sendable {
    private var v: T?
    func set(_ x: T) { v = x }
    var value: T { v! }
}
