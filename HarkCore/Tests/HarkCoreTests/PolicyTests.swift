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
    let range = LocalContext(LocalRange(cell: 0, present: [true, false, false, false, true], hasRange: [true, true, false, false, true]))

    func testHitsMaybesUnusual() {
        let p = Self.legacy()
        let t = p.triage(scores: [0.5, 0.35, 0.45, 0.4, 0.2], labels: labels, context: range)
        XCTAssertEqual(t.hits.map(\.index), [0, 2, 3])     // cricket has no range data -> passes; insect threshold 0.4
        XCTAssertEqual(t.unusual.map(\.index), [1])
        XCTAssertEqual(t.maybes.map(\.index), [4])          // 0.2 is between 0.15 and 0.3
    }

    func testHideAndOff() {
        var p = Self.legacy(.hide)
        var t = p.triage(scores: [0.5, 0.35, 0, 0, 0], labels: labels, context: range)
        XCTAssertEqual(t.hits.map(\.index), [0]); XCTAssertTrue(t.unusual.isEmpty)
        p.rangeMode = .off
        t = p.triage(scores: [0.5, 0.35, 0, 0, 0], labels: labels, context: range)
        XCTAssertEqual(t.hits.map(\.index), [0, 1])
    }

    func testOutOfRangeNeverAMaybe() {
        let t = Self.legacy().triage(scores: [0, 0.2, 0, 0, 0], labels: labels, context: range)
        XCTAssertTrue(t.maybes.isEmpty)
    }

    func testGroupSwitchAndThresholdAndMute() {
        var p = Self.legacy()
        p.set(.insect, GroupSetting(enabled: false, threshold: 0.4))
        p.set(.sound, GroupSetting(enabled: true, threshold: 0.6))
        let t = p.triage(scores: [0.5, 0, 0.9, 0.5, 0.31], labels: labels, context: range, muted: [0])
        XCTAssertEqual(t.hits.map(\.index), [4])            // cardinal muted, insects off, car under 0.6
        XCTAssertTrue(t.maybes.isEmpty)                     // sounds are never maybes
    }

    func testNoLocationMeansNoFiltering() {
        let t = Self.legacy().triage(scores: [0, 0.35, 0, 0, 0], labels: labels, context: nil)
        XCTAssertEqual(t.hits.map(\.index), [1])
    }

    func testSeasonAndOverrides() {
        // geomodel knows 0 (cardinal, here this week), 1 (robin, never here), 4 (chickadee, here but not this week);
        // 2 (cricket) only has GBIF data.
        let gbif = LocalRange(cell: 0, present: [true, false, true, false, true], hasRange: [true, true, true, false, true])
        let geo = LocalContext.Geo(week: [0.9, 0.001, nil, nil, 0.01], yearMax: [0.95, 0.002, nil, nil, 0.8])
        var c = LocalContext(count: 5, range: gbif, geo: geo)
        XCTAssertEqual(c.status(0), .expected); XCTAssertEqual(c.source(0), .geomodel)
        XCTAssertEqual(c.status(1), .outOfRange)
        XCTAssertEqual(c.status(2), .expected); XCTAssertEqual(c.source(2), .gbif)
        XCTAssertEqual(c.status(4), .outOfSeason)
        XCTAssertEqual(c.expectedThisWeek, 1)
        let t = Self.legacy().triage(scores: [0.5, 0, 0, 0, 0.6], labels: labels, context: c)
        XCTAssertEqual(t.hits.map(\.index), [0]); XCTAssertEqual(t.unusual.map(\.index), [4])
        // eBird reports and your own patch beat the model
        c = LocalContext(count: 5, range: gbif, geo: geo, patch: [1], ebird: [4])
        XCTAssertEqual(c.status(1), .expected); XCTAssertEqual(c.source(1), .patch)
        XCTAssertEqual(c.status(4), .expected); XCTAssertEqual(c.source(4), .ebird)
        // geomodel says never, GBIF has a record nearby: a rarity, flagged (shown, logged by hand)
        let rare = LocalContext(count: 5, range: LocalRange(cell: 0, present: [false, true, false, false, false], hasRange: [true, true, false, false, true]), geo: geo)
        XCTAssertEqual(rare.status(1), .rare)
        let rt = Self.legacy().triage(scores: [0, 0.6, 0, 0, 0], labels: labels, context: rare)
        XCTAssertTrue(rt.hits.isEmpty); XCTAssertEqual(rt.unusual.map(\.index), [1])
    }

    func testFusion() {
        XCTAssertEqual(Fusion.perchEquivalent(0.75), 0.30, accuracy: 1e-4)
        XCTAssertLessThan(Fusion.perchEquivalent(0.5), 0.2)
        XCTAssertGreaterThan(Fusion.perchEquivalent(0.97), 0.6)
        let p = Self.legacy()     // Balanced: birds 0.30, insects 0.40, sounds 0.30
        // cardinal: both lukewarm (agree) -> hit; robin: Perch only, lukewarm -> maybe; cricket: BirdNET+ sure -> hit
        let perch: [Float] = [0.26, 0.20, 0.0, 0, 0]
        let bn: [Float] = [0.15, 0.0, 0.60, 0, 0]
        let t = p.triage(scores: perch, second: bn, labels: labels, context: nil)
        XCTAssertEqual(t.hits.map(\.index), [0, 2])
        XCTAssertEqual(t.agreed, [0])
        XCTAssertEqual(t.maybes.map(\.index), [1])
        XCTAssertGreaterThanOrEqual(t.hits[0].confidence, 0.30)
    }

    func testGeoWeek() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day))! }
        XCTAssertEqual(GeoWeek.of(d(1, 1), calendar: cal), 1)
        XCTAssertEqual(GeoWeek.of(d(5, 15), calendar: cal), 19)
        XCTAssertEqual(GeoWeek.of(d(11, 21), calendar: cal), 43)
        XCTAssertEqual(GeoWeek.of(d(12, 31), calendar: cal), 48)
    }

    /// The logic tests below were written for 0.30 (0.40 for insects / other) bars; keep them independent of the presets.
    static func legacy(_ mode: RangeMode = .flag) -> DetectionPolicy {
        var p = DetectionPolicy(rangeMode: mode)
        for g in ListenGroup.allCases { p.set(g, GroupSetting(threshold: g == .insect || g == .other ? 0.4 : 0.3)) }
        return p
    }

    func testPresets() {
        var p = DetectionPolicy()
        XCTAssertEqual(p.preset, .balanced)                 // defaults are Balanced
        XCTAssertEqual(Fusion.display(p.setting(.bird).threshold), 0.85, accuracy: 0.002)    // shown like BirdNET's 85%
        XCTAssertEqual(Fusion.display(p.setting(.insect).threshold), 0.90, accuracy: 0.002)
        p.set(.insect, GroupSetting(enabled: false, threshold: 0.4))
        p.apply(.strict)
        XCTAssertEqual(p.preset, .strict)
        XCTAssertEqual(Fusion.display(p.setting(.bird).threshold), 0.92, accuracy: 0.002)
        XCTAssertFalse(p.setting(.insect).enabled)          // switches survive a preset
        p.set(.bird, GroupSetting(threshold: 0.42))
        XCTAssertNil(p.preset)                              // fine-tuned = Custom
    }

    func testDisplayScale() {
        XCTAssertEqual(Fusion.display(0.30), 0.75, accuracy: 1e-4)
        XCTAssertEqual(Fusion.display(0.50), 0.893, accuracy: 0.002)
        for d: Float in [0.6, 0.75, 0.85, 0.92] { XCTAssertEqual(Fusion.display(Fusion.fromDisplay(d)), d, accuracy: 1e-4) }
    }

    func testLegacyPresetMigrates() {
        var p = Self.legacy()                               // the old Balanced: 0.30 / 0.40
        p.set(.reptile, GroupSetting(enabled: false, threshold: 0.3))
        p.migrateLegacyPresets()
        XCTAssertEqual(p.preset, .balanced)
        XCTAssertFalse(p.setting(.reptile).enabled)
        var custom = Self.legacy(); custom.set(.bird, GroupSetting(threshold: 0.33))
        custom.migrateLegacyPresets()
        XCTAssertEqual(custom.setting(.bird).threshold, 0.33, accuracy: 1e-6)   // fine-tuned settings are left alone
    }

    func testMusicGateNeedsASureID() {
        // a cardinal at 0.45 is a hit; with music in the window it isn't, unless sure (Perch >= 0.70)
        let p = Self.legacy()
        XCTAssertEqual(p.triage(scores: [0.45, 0, 0, 0, 0], labels: labels, context: nil).hits.map(\.index), [0])
        XCTAssertTrue(p.triage(scores: [0.45, 0, 0, 0, 0], labels: labels, context: nil, humanSound: 0.3).hits.isEmpty)
        XCTAssertEqual(p.triage(scores: [0.75, 0, 0, 0, 0], labels: labels, context: nil, humanSound: 0.3).hits.map(\.index), [0])
    }

    func testPetSoundsPoolOntoTheSpecies() {
        let t = LabelTable(labels: [
            Label(scientific: "Canis familiaris", common: "Domestic Dog", group: .mammal),
            Label(scientific: "Dog", common: "Dog", group: .sound),
            Label(scientific: "Bark", common: "Bark", group: .sound),
            Label(scientific: "Car", common: "Car", group: .sound),
        ])
        var p: [Float] = [0.05, 0.25, 0.15, 0.10]   // a bark as Perch hears it: mostly the sound classes
        Fusion.poolSynonyms(&p, Fusion.synonymIndices(t))
        XCTAssertEqual(p[0], 0.45, accuracy: 1e-5)
        XCTAssertEqual(p[1], 0); XCTAssertEqual(p[2], 0); XCTAssertEqual(p[3], 0.10)
        XCTAssertEqual(DetectionPolicy().triage(scores: p, labels: t, context: nil).hits.map(\.index), [0])
    }

    func testLabelEmojiAndLookup() throws {
        let json = #"[{"s":"Strix varia","c":"Barred Owl","g":"bird","e":"🦉","i":19893},{"s":"Car","c":"Car","g":"sound"}]"#
        let t = LabelTable(labels: try JSONDecoder().decode([Label].self, from: Data(json.utf8)))
        XCTAssertEqual(t.label(scientific: "Strix varia")?.icon, "🦉")
        XCTAssertEqual(t.label(scientific: "Strix varia")?.inat, 19893)
        XCTAssertEqual(t[1].icon, "❔")
    }

    func testPolicyRoundTripsThroughJSON() throws {
        var p = Self.legacy(.hide)
        p.set(.amphibian, GroupSetting(enabled: false, threshold: 0.55))
        let back = try JSONDecoder().decode(DetectionPolicy.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testRangeMapFile() throws {
        // 2 cells: Madison's cell has species 0 and 4; a cell in England has 1.
        let map = try RangeMap(data: Self.file(cols: 256, rows: 128, species: 5, cells: [
            (RangeMapTestCell.madison, [0, 4]), (RangeMapTestCell.london, [1]),
        ]))
        XCTAssertEqual(map.cell(latitude: 43.07, longitude: -89.40), RangeMapTestCell.madison)
        let here = map.local(latitude: 43.07, longitude: -89.40)
        XCTAssertEqual(here.status(0), .inRange)
        XCTAssertEqual(here.status(1), .outOfRange)
        XCTAssertEqual(here.status(2), .unknown)
        XCTAssertEqual(here.speciesHere, 2)
        XCTAssertEqual(map.local(latitude: 51.5, longitude: -0.1).status(1), .inRange)
    }

    enum RangeMapTestCell {
        static let madison = 94 * 256 + 64     // 43.07 N, 89.40 W
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
