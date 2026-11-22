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
        var tr = DetectionTracker(gap: 60, confirmWindows: 1)
        tr.add(WindowResult(time: t0, hits: [(7, 0.4)]))
        let c = tr.add(WindowResult(time: t0 + 30, hits: [(7, 0.8)]))
        XCTAssertEqual(tr.occurrences.count, 1)
        XCTAssertEqual(tr.occurrences[0].bestConfidence, 0.8)
        XCTAssertEqual(tr.occurrences[0].windows, 2)
        guard case .updated = c[0] else { return XCTFail("expected update") }
    }
    func testGapStartsNewOccurrence() {
        var tr = DetectionTracker(gap: 60, confirmWindows: 1)
        tr.add(WindowResult(time: t0, hits: [(7, 0.4)]))
        let c = tr.add(WindowResult(time: t0 + 61, hits: [(7, 0.5)]))
        XCTAssertEqual(tr.occurrences.count, 2)
        guard case .started = c[0] else { return XCTFail("expected start") }
    }
    func testOneWindowBlipIsNotLogged() {
        var tr = DetectionTracker()                       // default: 2 windows within 5 s
        XCTAssertTrue(tr.add(WindowResult(time: t0, hits: [(7, 0.4)])).isEmpty)
        XCTAssertTrue(tr.occurrences.isEmpty)
        // a second hit 6 s later is too late to confirm the first: still pending
        XCTAssertTrue(tr.add(WindowResult(time: t0 + 6, hits: [(7, 0.4)])).isEmpty)
        // confirmed by a hit within 5 s; first heard is kept from the first of the pair
        let c = tr.add(WindowResult(time: t0 + 7, hits: [(7, 0.6)]))
        guard case .started(let o) = c.first else { return XCTFail("expected start") }
        XCTAssertEqual(o.firstHeard, t0 + 6)
        XCTAssertEqual(o.windows, 2)
        XCTAssertEqual(o.bestConfidence, 0.6)
    }

    func testActiveSortsByConfidence() {
        var tr = DetectionTracker(confirmWindows: 1)
        tr.add(WindowResult(time: t0, hits: [(1, 0.3), (2, 0.9)]))
        XCTAssertEqual(tr.active(at: t0 + 1, within: 8).map(\.index), [2, 1])
        tr.add(WindowResult(time: t0 + 20, hits: [(3, 0.5)]))
        XCTAssertEqual(tr.active(at: t0 + 21, within: 8).map(\.index), [3])
    }
}

final class WindowingTests: XCTestCase {
    func testShortStretchIsCenteredAndPadded() {
        XCTAssertEqual(Windowing.starts(length: 100, window: 10, hop: 5), [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90])
        XCTAssertEqual(Windowing.starts(length: 4, window: 10, hop: 5), [-3])
        let w = Windowing.window([1, 2, 3, 4], start: -3, window: 10)
        XCTAssertEqual(w, [0, 0, 0, 1, 2, 3, 4, 0, 0, 0])
    }
    func testLastWindowAlignsToEnd() {
        XCTAssertEqual(Windowing.starts(length: 23, window: 10, hop: 5), [0, 5, 10, 13])
        XCTAssertEqual(Windowing.window(Array(1...23).map(Float.init), start: 13, window: 10).last, 23)
    }
    func testMaxPool() {
        XCTAssertEqual(Windowing.maxPool([[0.1, 0.9], [0.5, 0.2]]), [0.5, 0.9])
    }
}
