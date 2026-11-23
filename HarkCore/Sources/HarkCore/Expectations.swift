import Foundation

/// What Hark expects to hear at a place and time, one status per label. Built from every source Hark has,
/// most trusted first:
///  1. eBird: reported within ~25 km in the last 30 days (optional, needs the user's own API key)
///  2. your patch: species you've confirmed near here
///  3. the BirdNET geomodel: place + week of the year (12,258 Perch species)
///  4. the GBIF range map: place only (everything else with GBIF records)
public struct LocalContext: Sendable, Equatable {
    /// rare: the geomodel never expects it here but GBIF has a record in the cell (often one vagrant). Flagged, so a
    /// single weak hit isn't logged as a state rarity.
    public enum Status: UInt8, Sendable { case unknown, expected, outOfRange, outOfSeason, rare }
    public enum Source: UInt8, Sendable { case none, ebird, patch, geomodel, gbif }

    private let statuses: [UInt8]
    private let sources: [UInt8]
    /// Species the geomodel expects this week (for "expecting N species here").
    public let expectedThisWeek: Int
    public let reportedNearby: Int

    public func status(_ i: Int) -> Status { i < statuses.count ? Status(rawValue: statuses[i]) ?? .unknown : .unknown }
    public func source(_ i: Int) -> Source { i < sources.count ? Source(rawValue: sources[i]) ?? .none : .none }
    public var isFlagging: Bool { statuses.contains { $0 >= Status.outOfRange.rawValue } }

    /// Geomodel output for one place: probability this week and the most it reaches in any week, per label
    /// (nil where the geomodel doesn't know the species).
    public struct Geo: Sendable, Equatable {
        public let week: [Float?]
        public let yearMax: [Float?]
        public init(week: [Float?], yearMax: [Float?]) { self.week = week; self.yearMax = yearMax }
    }

    /// BirdNET's own location filter default.
    public static let geoThreshold: Float = 0.03

    public init(count: Int, range: LocalRange? = nil, geo: Geo? = nil, patch: Set<Int> = [], ebird: Set<Int> = []) {
        var st = [UInt8](repeating: Status.unknown.rawValue, count: count)
        var src = [UInt8](repeating: Source.none.rawValue, count: count)
        var weekCount = 0
        for i in 0..<count {
            func set(_ s: Status, _ o: Source) { st[i] = s.rawValue; src[i] = o.rawValue }
            let gbif = range?.status(i) ?? .unknown
            if let geo, i < geo.week.count, let p = geo.week[i], p >= Self.geoThreshold { weekCount += 1 }
            if ebird.contains(i) { set(.expected, .ebird); continue }
            if patch.contains(i) { set(.expected, .patch); continue }
            if let geo, i < geo.week.count, let p = geo.week[i] {
                if p >= Self.geoThreshold { set(.expected, .geomodel) }
                else if let y = geo.yearMax[i], y >= Self.geoThreshold { set(.outOfSeason, .geomodel) }
                // The geomodel never expects it here, but GBIF has a record nearby: a rarity. Flag it (shown, logged by hand).
                else if gbif == .inRange { set(.rare, .gbif) }
                else { set(.outOfRange, .geomodel) }
                continue
            }
            switch gbif {
            case .inRange: set(.expected, .gbif)
            case .outOfRange: set(.outOfRange, .gbif)
            case .unknown: break
            }
        }
        statuses = st; sources = src; expectedThisWeek = weekCount; reportedNearby = ebird.count
    }

    /// GBIF range only (tests, and before the geomodel has run).
    public init(_ range: LocalRange) { self.init(count: range.present.count, range: range) }
}

/// BirdNET geomodel week: 48 per year, four per month (days 1-7, 8-14, 15-21, 22-end).
public enum GeoWeek {
    public static func of(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.month, .day], from: date)
        return ((c.month ?? 1) - 1) * 4 + min(4, ((c.day ?? 1) - 1) / 7 + 1)
    }
}
