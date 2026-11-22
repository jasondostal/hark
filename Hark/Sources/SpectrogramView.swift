import SwiftUI
import Accelerate
import CoreGraphics

/// Spectrogram math shared by the live view and touch-to-select: a 1024-point FFT every 10 ms (hop 320 at 32 kHz),
/// 128 mel bands (150 Hz to 15 kHz), log power over a per-band noise floor. Steady background (road rumble,
/// wind, furnace) fades to dark, and so does the natural low-frequency tilt. Each floor follows quiet quickly
/// and loud slowly (about 3 s), so a call doesn't raise its own floor. Not thread-safe; one per stream.
final class SpectrogramDSP {
    static let bins = 128, n = 1024, hop = 320
    static let columnsPerSecond = 100
    private static let log2n: vDSP_Length = 10
    private static let sr: Float = 32_000
    private static let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
    private static let mel = melBank()

    private let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    private var floorDB = [Float](repeating: -100, count: bins)
    private var warm = 0

    deinit { vDSP_destroy_fftsetup(setup) }

    func reset() { floorDB = [Float](repeating: -100, count: Self.bins); warm = 0 }

    /// One column of 128 display levels (0...255, low band first) from n samples starting at `frame`.
    func column(_ frame: UnsafePointer<Float>, into out: UnsafeMutablePointer<UInt8>) {
        let n = Self.n, half = n / 2
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, Self.window, 1, &windowed, 1, vDSP_Length(n))
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { fb in
                    vDSP_ctoz(fb.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                ip[0] = 0                                   // imag[0] holds Nyquist; drop it
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        var bands = [Float](repeating: 0, count: Self.bins)
        vDSP_mmul(Self.mel, 1, power, 1, &bands, 1, vDSP_Length(Self.bins), 1, vDSP_Length(half))
        let span = SpectrogramStyle.shared.span
        for b in 0..<Self.bins {
            let db = 10 * log10f(bands[b] + 1e-12)
            if warm < 30 { floorDB[b] = warm == 0 ? db : min(floorDB[b], db) + 0.3 }
            else { floorDB[b] += (db - floorDB[b]) * (db < floorDB[b] ? 0.03 : 0.003) }
            out[b] = UInt8(min(max((db - floorDB[b] - 4) / span, 0), 1) * 255)
        }
        warm += 1
    }

    /// Whole-clip spectrogram (selections, saved clips): column-major levels, 128 per column.
    static func levels(of samples: [Float]) -> (data: [UInt8], columns: Int) {
        guard samples.count >= n else { return ([], 0) }
        let cols = (samples.count - n) / hop + 1
        var data = [UInt8](repeating: 0, count: cols * bins)
        let dsp = SpectrogramDSP()
        samples.withUnsafeBufferPointer { s in
            data.withUnsafeMutableBufferPointer { d in
                for c in 0..<cols { dsp.column(s.baseAddress! + c * hop, into: d.baseAddress! + c * bins) }
            }
        }
        return (data, cols)
    }

    /// Image of columns `range` from column-major levels (low band at the bottom).
    static func image(_ levels: [UInt8], columns: Int, range: Range<Int>? = nil) -> CGImage? {
        let r = (range ?? 0..<columns).clamped(to: 0..<columns)
        guard !r.isEmpty else { return nil }
        let w = r.count, h = bins
        let lut = SpectrogramStyle.shared.lut
        var px = [UInt32](repeating: lut[0], count: w * h)
        for x in 0..<w {
            let base = (r.lowerBound + x) * h
            for b in 0..<h { px[(h - 1 - b) * w + x] = lut[Int(levels[base + b])] }
        }
        return cgImage(&px, w, h)
    }

    static func cgImage(_ px: inout [UInt32], _ w: Int, _ h: Int) -> CGImage? {
        px.withUnsafeMutableBytes { buf in
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

    /// Height fraction (0 = bottom) of a frequency on the display's mel axis.
    static func yFraction(hz: Float) -> CGFloat {
        func mel(_ f: Float) -> Float { 2595 * log10f(1 + f / 700) }
        return CGFloat((mel(hz) - mel(150)) / (mel(15_000) - mel(150)))
    }
}

/// Real-time scrolling spectrogram, separate from Perch. Fed on the audio thread, drawn at display rate.
/// The playhead trails the newest audio by about 200 ms so the mic's ~100 ms chunk bursts scroll smoothly.
final class LiveSpectrogram: @unchecked Sendable {
    static let maxSeconds = 30
    private static let bins = SpectrogramDSP.bins
    private static let capacity = maxSeconds * SpectrogramDSP.columnsPerSecond + 128
    private static let lag = 20.0             // columns (200 ms)
    private static let maxImageWidth = 600    // wider spans pool neighboring columns (max) down to this

    private let lock = NSLock()
    private let dsp = SpectrogramDSP()
    private var tail: [Float] = []
    private var ring = [UInt8](repeating: 0, count: capacity * bins)
    private var produced = 0
    private var playhead = 0.0
    private var lastDraw: Double = 0
    private var seconds = 10

    /// How much time fits across the screen (5...30 s).
    func setSeconds(_ s: Int) { lock.lock(); seconds = min(max(s, 1), Self.maxSeconds); lock.unlock() }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        tail = []; produced = 0; playhead = 0; lastDraw = 0; dsp.reset()
        for i in ring.indices { ring[i] = 0 }
    }

    /// Audio thread: 32 kHz mono samples in, spectrogram columns out.
    func append(_ s: [Float]) {
        lock.lock(); defer { lock.unlock() }
        tail += s
        var off = 0
        tail.withUnsafeBufferPointer { t in
            ring.withUnsafeMutableBufferPointer { r in
                while t.count - off >= SpectrogramDSP.n {
                    dsp.column(t.baseAddress! + off, into: r.baseAddress! + (produced % Self.capacity) * Self.bins)
                    produced += 1
                    off += SpectrogramDSP.hop
                }
            }
        }
        if off > 0 { tail.removeFirst(off) }
    }

    /// How far the right edge of the screen trails the newest audio, in samples (to freeze exactly what's shown).
    func lagSamples() -> Int {
        lock.lock(); defer { lock.unlock() }
        return max(0, Int((Double(produced) - playhead) * Double(SpectrogramDSP.hop))) + tail.count
    }

    struct Frame { let image: CGImage; let groups: Int; let fraction: CGFloat }

    /// Main thread, once per display frame. The image holds groups+1 columns (each the max of k raw columns,
    /// grouped on absolute column numbers so they don't shimmer); draw it groups+1 wide and shift it left by
    /// `fraction` of a column so scrolling is smooth even when one image column spans several pixels.
    func frame(now: Double) -> Frame? {
        lock.lock(); defer { lock.unlock() }
        guard produced > 0 else { return nil }
        let dt = lastDraw == 0 ? 0 : min(max(now - lastDraw, 0), 0.1)
        lastDraw = now
        let target = Double(produced) - Self.lag
        playhead += dt * Double(SpectrogramDSP.columnsPerSecond)   // real time
        playhead += (target - playhead) * 0.06                     // ease toward the newest audio
        if abs(target - playhead) > 60 { playhead = target }       // far off (start, resume): jump
        playhead = min(playhead, Double(produced))

        let visible = seconds * SpectrogramDSP.columnsPerSecond
        let k = max(1, Int((Double(visible) / Double(Self.maxImageWidth)).rounded(.up)))
        let n = visible / k
        let pos = max(playhead, 0) / Double(k)
        let endGroup = Int(pos.rounded(.down))
        let w = n + 1, h = Self.bins
        let lut = SpectrogramStyle.shared.lut
        var px = [UInt32](repeating: lut[0], count: w * h)
        var col = [UInt8](repeating: 0, count: h)
        let oldest = produced - Self.capacity
        for x in 0..<w {
            let g = endGroup - n + x
            for b in 0..<h { col[b] = 0 }
            var any = false
            for c in (g * k)..<(g * k + k) where c >= 0 && c > oldest && c < produced {
                let base = (c % Self.capacity) * h
                for b in 0..<h where ring[base + b] > col[b] { col[b] = ring[base + b] }
                any = true
            }
            guard any else { continue }
            for b in 0..<h { px[(h - 1 - b) * w + x] = lut[Int(col[b])] }
        }
        guard let img = SpectrogramDSP.cgImage(&px, w, h) else { return nil }
        return Frame(image: img, groups: n, fraction: CGFloat(pos - Double(endGroup)))
    }
}

struct SpectrogramView: View {
    let source: LiveSpectrogram
    let running: Bool
    var palette: SpectrogramPalette = .aurora
    var frequencyLabels = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !running)) { tl in
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    palette.background
                    if let f = source.frame(now: tl.date.timeIntervalSinceReferenceDate) {
                        let colW = g.size.width / CGFloat(f.groups)
                        Image(decorative: f.image, scale: 1).resizable().interpolation(.medium)
                            .frame(width: g.size.width + colW, height: g.size.height)
                            .offset(x: -f.fraction * colW)
                    } else {
                        Text("Tap Listen to start").font(.callout).foregroundStyle(palette.labelColor)
                            .frame(width: g.size.width, height: g.size.height)
                    }
                }
                .clipped()
            }
        }
        .overlay(alignment: .leading) { if frequencyLabels { FrequencyAxis(color: palette.labelColor) } }
    }
}

/// kHz ticks on the mel axis, so you can tell a 2 kHz owl from an 8 kHz warbler.
struct FrequencyAxis: View {
    var color: Color = .white.opacity(0.7)
    var body: some View {
        GeometryReader { g in
            ForEach([1, 2, 4, 8], id: \.self) { k in
                let y = g.size.height * (1 - SpectrogramDSP.yFraction(hz: Float(k * 1000)))
                HStack(spacing: 3) {
                    Rectangle().fill(color.opacity(0.6)).frame(width: 6, height: 1)
                    Text("\(k)k").font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(color)
                }
                .position(x: 16, y: y)
            }
        }
        .allowsHitTesting(false)
    }
}
