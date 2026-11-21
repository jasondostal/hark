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
    enum CodingKeys: String, CodingKey { case scientific = "s", common = "c", group = "g" }
}

/// Class index -> label, in the model's output order (built by tools/make_labels.py).
public struct LabelTable: Sendable {
    public let labels: [Label]
    public init(labels: [Label]) { self.labels = labels }
    public init(contentsOf url: URL) throws {
        labels = try JSONDecoder().decode([Label].self, from: Data(contentsOf: url))
    }
    public subscript(i: Int) -> Label { labels[i] }
    public var count: Int { labels.count }
    public func index(ofScientific s: String) -> Int? { labels.firstIndex { $0.scientific == s } }
}
