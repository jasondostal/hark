import Foundation

/// Which species have been recorded where: a global 1.40625-degree grid built from GBIF occurrence records
/// by tools/gbif_ranges.py (format documented there). Species never seen in any cell have no range data
/// and are never treated as out of range.
public struct RangeMap: Sendable {
    public let cols: Int, rows: Int
    public let speciesCount: Int
    /// true for classes that appear in at least one cell
    public let hasRange: [Bool]
    private let data: Data
    private let index: [UInt32: (offset: Int, count: Int)]
    private let bodyStart: Int

    public enum Status: Sendable, Equatable { case inRange, outOfRange, unknown }

    public init(contentsOf url: URL) throws { try self.init(data: Data(contentsOf: url, options: .mappedIfSafe)) }

    public init(data: Data) throws {
        func u16(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) }.littleEndian) }
        func u32(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }.littleEndian) }
        guard data.count >= 16, data.prefix(4) == Data("HRNG".utf8), u16(4) == 1 else {
            throw NSError(domain: "RangeMap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a Hark range file"])
        }
        cols = u16(6); rows = u16(8); speciesCount = u16(10)
        let nCells = u32(12)
        var idx: [UInt32: (Int, Int)] = [:]
        idx.reserveCapacity(nCells)
        var total = 0
        for k in 0..<nCells {
            let o = 16 + k * 10
            let n = u16(o + 8)
            idx[UInt32(u32(o))] = (u32(o + 4), n)
            total = max(total, u32(o + 4) + n)
        }
        bodyStart = 16 + nCells * 10
        guard data.count >= bodyStart + total * 2 else {
            throw NSError(domain: "RangeMap", code: 2, userInfo: [NSLocalizedDescriptionKey: "Range file truncated"])
        }
        var has = [Bool](repeating: false, count: speciesCount)
        let start = bodyStart
        data.withUnsafeBytes { raw in
            for i in 0..<total {
                let s = Int(raw.loadUnaligned(fromByteOffset: start + i * 2, as: UInt16.self).littleEndian)
                if s < has.count { has[s] = true }
            }
        }
        self.data = data; index = idx; hasRange = has
    }

    public func cell(latitude: Double, longitude: Double) -> Int {
        let r = min(max(Int((latitude + 90) / 180 * Double(rows)), 0), rows - 1)
        let c = min(max(Int((longitude + 180) / 360 * Double(cols)), 0), cols - 1)
        return r * cols + c
    }

    /// Species recorded in one cell.
    public func species(inCell cell: Int) -> [Int] {
        guard let e = index[UInt32(cell)] else { return [] }
        let start = bodyStart + e.offset * 2
        return data.withUnsafeBytes { raw in
            (0..<e.count).map { Int(raw.loadUnaligned(fromByteOffset: start + $0 * 2, as: UInt16.self).littleEndian) }
        }
    }

    public func local(latitude: Double, longitude: Double) -> LocalRange {
        let c = cell(latitude: latitude, longitude: longitude)
        var mask = [Bool](repeating: false, count: speciesCount)
        for s in species(inCell: c) where s < mask.count { mask[s] = true }
        return LocalRange(cell: c, present: mask, hasRange: hasRange)
    }
}

/// The range filter for the cell you're standing in.
public struct LocalRange: Sendable, Equatable {
    public let cell: Int
    public let present: [Bool]
    public let hasRange: [Bool]
    public init(cell: Int, present: [Bool], hasRange: [Bool]) { self.cell = cell; self.present = present; self.hasRange = hasRange }
    public var speciesHere: Int { present.reduce(0) { $0 + ($1 ? 1 : 0) } }
    public func status(_ i: Int) -> RangeMap.Status {
        guard i < hasRange.count, hasRange[i] else { return .unknown }
        return present[i] ? .inRange : .outOfRange
    }
}
