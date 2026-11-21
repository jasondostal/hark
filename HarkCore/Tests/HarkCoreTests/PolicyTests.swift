import XCTest
@testable import HarkCore

final class PolicyTests: XCTestCase {
    // 0 cardinal (bird, in range), 1 European robin (bird, out of range), 2 cricket (insect, no range data),
    // 3 car (sound), 4 chickadee (bird, in range)
    let labels = LabelTable(labels: [
        Label(scientific: "Cardinalis cardinalis", common: "Northern Cardinal", group: .bird),
        Label(scientific: "Erithacus rubecula", common: "European Robin", group: .bird),
        Label(scientific: "Oecanthus fultoni", common: "Snowy Tree Cricket", group: .insect),
        Label(scientific: "Car", common: "Car", group: .sound),
        Label(scientific: "Poecile atricapillus", common: "Black-capped Chickadee", group: .bird),
    ])
    let range = LocalRange(cell: 0, present: [true, false, false, false, true], hasRange: [true, true, false, false, true])

    func testHitsMaybesUnusual() {
        let p = DetectionPolicy()
        let t = p.triage(scores: [0.5, 0.35, 0.45, 0.4, 0.2], labels: labels, range: range)
        XCTAssertEqual(t.hits.map(\.index), [0, 2, 3])     // cricket has no range data -> passes; insect threshold 0.4
        XCTAssertEqual(t.unusual.map(\.index), [1])
        XCTAssertEqual(t.maybes.map(\.index), [4])          // 0.2 is between 0.15 and 0.3
    }

    func testHideAndOff() {
        var p = DetectionPolicy(rangeMode: .hide)
        var t = p.triage(scores: [0.5, 0.35, 0, 0, 0], labels: labels, range: range)
        XCTAssertEqual(t.hits.map(\.index), [0]); XCTAssertTrue(t.unusual.isEmpty)
        p.rangeMode = .off
        t = p.triage(scores: [0.5, 0.35, 0, 0, 0], labels: labels, range: range)
        XCTAssertEqual(t.hits.map(\.index), [0, 1])
    }

    func testOutOfRangeNeverAMaybe() {
        let t = DetectionPolicy().triage(scores: [0, 0.2, 0, 0, 0], labels: labels, range: range)
        XCTAssertTrue(t.maybes.isEmpty)
    }

    func testGroupSwitchAndThresholdAndMute() {
        var p = DetectionPolicy()
        p.set(.insect, GroupSetting(enabled: false, threshold: 0.4))
        p.set(.sound, GroupSetting(enabled: true, threshold: 0.6))
        let t = p.triage(scores: [0.5, 0, 0.9, 0.5, 0.31], labels: labels, range: range, muted: [0])
        XCTAssertEqual(t.hits.map(\.index), [4])            // cardinal muted, insects off, car under 0.6
        XCTAssertTrue(t.maybes.isEmpty)                     // sounds are never maybes
    }

    func testNoLocationMeansNoFiltering() {
        let t = DetectionPolicy().triage(scores: [0, 0.35, 0, 0, 0], labels: labels, range: nil)
        XCTAssertEqual(t.hits.map(\.index), [1])
    }

    func testPresets() {
        var p = DetectionPolicy()
        XCTAssertEqual(p.preset, .balanced)                 // defaults are Balanced
        p.set(.insect, GroupSetting(enabled: false, threshold: 0.4))
        p.apply(.strict)
        XCTAssertEqual(p.preset, .strict)
        XCTAssertEqual(p.setting(.bird).threshold, 0.5, accuracy: 1e-6)
        XCTAssertEqual(p.setting(.insect).threshold, 0.6, accuracy: 1e-6)
        XCTAssertFalse(p.setting(.insect).enabled)          // switches survive a preset
        p.set(.bird, GroupSetting(threshold: 0.42))
        XCTAssertNil(p.preset)                              // fine-tuned = Custom
    }

    func testLabelEmojiAndLookup() throws {
        let json = #"[{"s":"Strix varia","c":"Barred Owl","g":"bird","e":"🦉","i":19893},{"s":"Car","c":"Car","g":"sound"}]"#
        let t = LabelTable(labels: try JSONDecoder().decode([Label].self, from: Data(json.utf8)))
        XCTAssertEqual(t.label(scientific: "Strix varia")?.icon, "🦉")
        XCTAssertEqual(t.label(scientific: "Strix varia")?.inat, 19893)
        XCTAssertEqual(t[1].icon, "❔")
    }

    func testPolicyRoundTripsThroughJSON() throws {
        var p = DetectionPolicy(rangeMode: .hide)
        p.set(.amphibian, GroupSetting(enabled: false, threshold: 0.55))
        let back = try JSONDecoder().decode(DetectionPolicy.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testRangeMapFile() throws {
        // 2 cells: Plover's cell has species 0 and 4; a cell in England has 1.
        let map = try RangeMap(data: Self.file(cols: 256, rows: 128, species: 5, cells: [
            (RangeMapTestCell.plover, [0, 4]), (RangeMapTestCell.london, [1]),
        ]))
        XCTAssertEqual(map.cell(latitude: 44.45, longitude: -89.55), RangeMapTestCell.plover)
        let here = map.local(latitude: 44.45, longitude: -89.55)
        XCTAssertEqual(here.status(0), .inRange)
        XCTAssertEqual(here.status(1), .outOfRange)
        XCTAssertEqual(here.status(2), .unknown)
        XCTAssertEqual(here.speciesHere, 2)
        XCTAssertEqual(map.local(latitude: 51.5, longitude: -0.1).status(1), .inRange)
    }

    enum RangeMapTestCell {
        static let plover = 95 * 256 + 64      // 44.45 N, 89.55 W
        static let london = 100 * 256 + 127    // 51.5 N, 0.1 W
    }

    static func file(cols: Int, rows: Int, species: Int, cells: [(Int, [Int])]) -> Data {
        var d = Data("HRNG".utf8)
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put(UInt16(1)); put(UInt16(cols)); put(UInt16(rows)); put(UInt16(species)); put(UInt32(cells.count))
        var off = 0
        for (c, s) in cells.sorted(by: { $0.0 < $1.0 }) { put(UInt32(c)); put(UInt32(off)); put(UInt16(s.count)); off += s.count }
        for (_, s) in cells.sorted(by: { $0.0 < $1.0 }) { for x in s { put(UInt16(x)) } }
        return d
    }
}
