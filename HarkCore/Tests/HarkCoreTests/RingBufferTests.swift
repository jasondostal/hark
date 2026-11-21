import XCTest
@testable import HarkCore

final class RingBufferTests: XCTestCase {
    func testLatestPadsFrontWhenShort() {
        var r = RingBuffer(capacity: 5)
        r.append([1, 2])
        XCTAssertEqual(r.latest(4), [0, 0, 1, 2])
    }
    func testWrapsKeepingNewest() {
        var r = RingBuffer(capacity: 5)
        r.append([1, 2, 3, 4])
        r.append([5, 6, 7])
        XCTAssertEqual(r.latest(5), [3, 4, 5, 6, 7])
        XCTAssertEqual(r.latest(2), [6, 7])
        XCTAssertEqual(r.totalWritten, 7)
    }
    func testOversizedAppendKeepsTail() {
        var r = RingBuffer(capacity: 3)
        r.append([1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(r.latest(3), [5, 6, 7])
        XCTAssertEqual(r.count, 3)
    }
    func testManySmallAppendsMatchOneBig() {
        var a = RingBuffer(capacity: 1000), b = RingBuffer(capacity: 1000)
        let x = (0..<2500).map { Float($0) }
        a.append(x)
        for c in stride(from: 0, to: x.count, by: 37) { b.append(Array(x[c..<min(c + 37, x.count)])) }
        XCTAssertEqual(a.latest(1000), b.latest(1000))
        XCTAssertEqual(a.latest(1000).first, 1500)
    }
}
