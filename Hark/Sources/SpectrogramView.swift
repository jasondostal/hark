import SwiftUI
import Accelerate
import CoreGraphics

/// Real-time scrolling spectrogram, separate from Perch: a 1024-point FFT every 10 ms (hop 320 at 32 kHz),
/// 128 mel bands (150 Hz to 15 kHz), log power over a slowly adapting noise floor.
/// It's fed on the audio thread and drawn at display rate. The playhead trails the newest audio by about
/// 200 ms so the mic's ~100 ms chunk bursts scroll smoothly instead of stepping.
final class LiveSpectrogram: @unchecked Sendable {
    static let visible = 500                  // 5 s on screen, the same span as one Perch window
    static let bins = 128
    private static let n = 1024, hop = 320, log2n: vDSP_Length = 10
    private static let sr: Float = 32_000
    private static let capacity = visible + 128
    private static let lag = 20.0             // columns (200 ms)

    private let lock = NSLock()
    private var tail: [Float] = []
    private var ring = [UInt8](repeating: 0, count: capacity * bins)   // per column: 128 levels, low band first
    private var produced = 0
    private var playhead = 0.0
    private var lastDraw: Double = 0
    private var floorDB = [Float](repeating: -100, count: bins)   // per-band noise floor
    private var warm = 0

    private let setup: FFTSetup
    private let window: [Float]
    private let mel: [Float]                  // bins x (n/2), row-major
    private let lut: [UInt32]

    init() {
        setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.n, isHalfWindow: false)
        mel = Self.melBank()
        lut = (0..<256).map { i in
            let (r, g, b) = Self.palette(Float(i) / 255)
            return UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | 0xFF00_0000
        }
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return produced == 0 }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        tail = []; produced = 0; playhead = 0; lastDraw = 0; warm = 0
        floorDB = [Float](repeating: -100, count: Self.bins)
        for i in ring.indices { ring[i] = 0 }
    }

    /// Audio thread: 32 kHz mono samples in, spectrogram columns out.
    func append(_ s: [Float]) {
        lock.lock(); defer { lock.unlock() }
        tail += s
        var off = 0
        while tail.count - off >= Self.n {
            column(at: off)
            off += Self.hop
        }
        if off > 0 { tail.removeFirst(off) }
    }

    private func column(at off: Int) {
        let n = Self.n, half = n / 2
        var frame = [Float](repeating: 0, count: n)
        tail.withUnsafeBufferPointer { p in vDSP_vmul(p.baseAddress! + off, 1, window, 1, &frame, 1, vDSP_Length(n)) }
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBytes { fb in
                    vDSP_ctoz(fb.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                ip[0] = 0                                   // imag[0] holds Nyquist; drop it
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        var bands = [Float](repeating: 0, count: Self.bins)
        vDSP_mmul(mel, 1, power, 1, &bands, 1, vDSP_Length(Self.bins), 1, vDSP_Length(half))

        let db = bands.map { 10 * log10f($0 + 1e-12) }
        // Per-band noise floor: steady background (road rumble, wind, furnace) fades to dark, and so does
        // the natural low-frequency tilt. Each floor follows quiet quickly and loud slowly (about 3 s), so a call
        // doesn't raise its own floor. The first 0.3 s seeds the floors directly.
        let base = (produced % Self.capacity) * Self.bins
        let span: Float = 36
        for b in 0..<Self.bins {
            if warm < 30 { floorDB[b] = warm == 0 ? db[b] : min(floorDB[b], db[b]) + 0.3 }
            else { floorDB[b] += (db[b] - floorDB[b]) * (db[b] < floorDB[b] ? 0.03 : 0.003) }
            let t = min(max((db[b] - floorDB[b] - 4) / span, 0), 1)
            ring[base + b] = UInt8(t * 255)
        }
        warm += 1
        produced += 1
    }

    /// Main thread, once per display frame: the newest 5 s as an image.
    func image(now: Double) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard produced > 0 else { return nil }
        let dt = lastDraw == 0 ? 0 : min(max(now - lastDraw, 0), 0.1)
        lastDraw = now
        let target = Double(produced) - Self.lag
        playhead += dt * 100                                  // real time: 100 columns per second
        playhead += (target - playhead) * 0.06                // ease toward the newest audio
        if abs(target - playhead) > 60 { playhead = target }  // far off (start, resume): jump
        playhead = min(playhead, Double(produced))

        let w = Self.visible, h = Self.bins
        let end = Int(playhead)
        var px = [UInt32](repeating: lut[0], count: w * h)
        for x in 0..<w {
            let c = end - w + x
            guard c >= 0, c > produced - Self.capacity else { continue }
            let base = (c % Self.capacity) * h
            for b in 0..<h { px[(h - 1 - b) * w + x] = lut[Int(ring[base + b])] }
        }
        return px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// Triangular mel filters, area-normalized so flat noise looks flat. Bands narrower than one FFT bin
    /// fall back to their nearest bin instead of going black.
    private static func melBank() -> [Float] {
        let half = n / 2, binHz = sr / Float(n)
        func mel(_ f: Float) -> Float { 2595 * log10f(1 + f / 700) }
        func hz(_ m: Float) -> Float { 700 * (powf(10, m / 2595) - 1) }
        let lo = mel(150), hi = mel(15_000)
        let pts = (0..<(bins + 2)).map { hz(lo + (hi - lo) * Float($0) / Float(bins + 1)) }
        var m = [Float](repeating: 0, count: bins * half)
        for b in 0..<bins {
            let l = pts[b], c = pts[b + 1], r = pts[b + 2]
            var sum: Float = 0
            for k in 0..<half {
                let f = Float(k) * binHz
                let w: Float = f <= l || f >= r ? 0 : (f <= c ? (f - l) / (c - l) : (r - f) / (r - c))
                m[b * half + k] = w * 2 / (r - l); sum += w
            }
            if sum == 0 { m[b * half + min(Int((c / binHz).rounded()), half - 1)] = 1 / binHz }
        }
        return m
    }

    // Dark blue -> teal -> yellow (perceptually ordered, readable on black).
    static func palette(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let stops: [(Float, Float, Float)] = [(0.02, 0.02, 0.08), (0.10, 0.20, 0.45), (0.10, 0.55, 0.55), (0.55, 0.80, 0.30), (0.99, 0.91, 0.15)]
        let x = t * Float(stops.count - 1)
        let i = min(Int(x), stops.count - 2), f = x - Float(i)
        let a = stops[i], b = stops[i + 1]
        func c(_ p: Float, _ q: Float) -> UInt8 { UInt8(max(0, min(255, (p + (q - p) * f) * 255))) }
        return (c(a.0, b.0), c(a.1, b.1), c(a.2, b.2))
    }
}

struct SpectrogramView: View {
    let source: LiveSpectrogram
    let running: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !running)) { tl in
            ZStack {
                Color.black
                if let img = source.image(now: tl.date.timeIntervalSinceReferenceDate) {
                    Image(decorative: img, scale: 1).resizable().interpolation(.medium)
                } else {
                    Text("Spectrogram").font(.caption).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }
}
