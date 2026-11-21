import XCTest
@testable import HarkCore

final class ScoringTests: XCTestCase {
    func testSoftmaxSumsToOneAndIsStable() {
        let p = Scoring.softmax([1000, 1001, 999])
        XCTAssertEqual(p.reduce(0, +), 1, accuracy: 1e-5)
        XCTAssertGreaterThan(p[1], p[0])
    }
    func testRestLogitLowersSliceScores() {
        let plain = Scoring.softmax([2, 1])
        let rest = Scoring.softmax([2, 1], restLogit: 3)
        XCTAssertLessThan(rest[0], plain[0])
        XCTAssertEqual(rest[0] + rest[1], 1 - Float(exp(3.0) / (exp(2.0) + exp(1.0) + exp(3.0))), accuracy: 1e-5)
    }
    func testTopK() {
        XCTAssertEqual(Scoring.topK([0.1, 0.9, 0.3, 0.7], 2), [1, 3])
        XCTAssertEqual(Scoring.topK([0.1, 0.9, 0.3], 1), [1])
        XCTAssertEqual(Scoring.topK([0.5], 3), [0])
    }
    func testWindowResultThreshold() {
        let w = WindowResult(time: .now, scores: [0.05, 0.6, 0.3, 0.05], threshold: 0.25)
        XCTAssertEqual(w.hits.map(\.index), [1, 2])
    }
}

final class TrackerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func testContinuousHearingIsOneOccurrence() {
        var tr = DetectionTracker(gap: 60)
        tr.add(WindowResult(time: t0, hits: [(7, 0.4)]))
        let c = tr.add(WindowResult(time: t0 + 30, hits: [(7, 0.8)]))
        XCTAssertEqual(tr.occurrences.count, 1)
        XCTAssertEqual(tr.occurrences[0].bestConfidence, 0.8)
        XCTAssertEqual(tr.occurrences[0].windows, 2)
        guard case .updated = c[0] else { return XCTFail("expected update") }
    }
    func testGapStartsNewOccurrence() {
        var tr = DetectionTracker(gap: 60)
        tr.add(WindowResult(time: t0, hits: [(7, 0.4)]))
        let c = tr.add(WindowResult(time: t0 + 61, hits: [(7, 0.5)]))
        XCTAssertEqual(tr.occurrences.count, 2)
        guard case .started = c[0] else { return XCTFail("expected start") }
    }
    func testActiveSortsByConfidence() {
        var tr = DetectionTracker()
        tr.add(WindowResult(time: t0, hits: [(1, 0.3), (2, 0.9)]))
        XCTAssertEqual(tr.active(at: t0 + 1, within: 8).map(\.index), [2, 1])
        tr.add(WindowResult(time: t0 + 20, hits: [(3, 0.5)]))
        XCTAssertEqual(tr.active(at: t0 + 21, within: 8).map(\.index), [3])
    }
}
