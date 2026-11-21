/// Fixed-capacity ring of audio samples. The newest `capacity` samples are kept; `latest(_:)` returns them oldest-first.
/// Not thread-safe; the owner serializes access (the app keeps it inside an actor).
public struct RingBuffer {
    public let capacity: Int
    private var storage: [Float]
    private var head = 0          // next write position
    public private(set) var count = 0
    /// Total samples ever appended (for timestamps).
    public private(set) var totalWritten: Int = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = [Float](repeating: 0, count: capacity)
    }

    public mutating func append(_ samples: UnsafeBufferPointer<Float>) {
        var src = samples[...]
        if src.count > capacity { src = src.suffix(capacity) }
        var i = src.startIndex
        while i < src.endIndex {
            let n = min(capacity - head, src.endIndex - i)
            storage.withUnsafeMutableBufferPointer { dst in
                for k in 0..<n { dst[head + k] = src[i + k] }
            }
            head = (head + n) % capacity
            i += n
        }
        count = min(capacity, count + src.count)
        totalWritten += samples.count
    }

    public mutating func append(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { append($0) }
    }

    /// The newest `n` samples, oldest first. Zero-padded at the front when fewer than `n` are held.
    public func latest(_ n: Int) -> [Float] {
        precondition(n <= capacity)
        var out = [Float](repeating: 0, count: n)
        let have = min(n, count)
        let start = (head - have + capacity) % capacity
        for k in 0..<have { out[n - have + k] = storage[(start + k) % capacity] }
        return out
    }

    public mutating func removeAll() { head = 0; count = 0 }
}
