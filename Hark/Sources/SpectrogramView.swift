import SwiftUI
import HarkCore
import Accelerate
import CoreGraphics

/// How the spectrogram is computed (Settings > Spectrogram). The models never see any of this.
struct SpectrogramConfig: Equatable, Sendable {
    /// FFT length: 512 (sharper in time, for fast trills), 1024, or 2048 (sharper in pitch, for close harmonics).
    var fft = 1024
    /// Top of the frequency axis in Hz (the audio is 32 kHz, so 16 kHz is the ceiling).
    var topHz: Float = 15_000
    /// Each band fades its own steady background (hum, wind, the low-end tilt). Off: one floor for all bands,
    /// so steady sounds and the true shape of the noise stay visible.
    var fadeBackground = true
    static let bottomHz: Float = 150
}

/// Spectrogram math shared by the live view and touch-to-select: an FFT (1024-point unless changed) every 10 ms
/// (hop 320 at 32 kHz), 128 mel bands (150 Hz to 15 kHz unless changed), log power over a per-band noise floor.
/// Steady background (road rumble, wind, furnace) fades to dark, and so does the natural low-frequency tilt. Each
/// floor follows quiet quickly and loud slowly (about 3 s), so a call doesn't raise its own floor. Not thread-safe;
/// one per stream.
final class SpectrogramDSP {
    static let bins = 128, hop = 320
    static let columnsPerSecond = 100
    private static let sr: Float = 32_000

    /// Window + mel filter bank for one config, built once and shared.
    private final class Tables: @unchecked Sendable {
        let window: [Float], mel: [Float]
        init(_ c: SpectrogramConfig) {
            window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: c.fft, isHalfWindow: false)
            mel = SpectrogramDSP.melBank(n: c.fft, topHz: c.topHz)
        }
    }
    private static let tableLock = NSLock()
    private static var tables: [String: Tables] = [:]
    private static func tables(for c: SpectrogramConfig) -> Tables {
        let key = "\(c.fft)-\(c.topHz)"
        tableLock.lock(); defer { tableLock.unlock() }
        if let t = tables[key] { return t }
        if tables.count > 6 { tables.removeAll() }
        let t = Tables(c); tables[key] = t; return t
    }

    let config: SpectrogramConfig
    /// Samples one column needs.
    var n: Int { config.fft }
    private let log2n: vDSP_Length
    private let table: Tables
    private let setup: FFTSetup
    private var floorDB = [Float](repeating: -100, count: bins)
    private var warm = 0

    init(_ config: SpectrogramConfig = SpectrogramStyle.shared.config) {
        self.config = config
        log2n = vDSP_Length(config.fft.trailingZeroBitCount)
        table = Self.tables(for: config)
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func reset() { floorDB = [Float](repeating: -100, count: Self.bins); warm = 0 }

    /// One column of 128 display levels (0...255, low band first) from n samples starting at `frame`.
    func column(_ frame: UnsafePointer<Float>, into out: UnsafeMutablePointer<UInt8>) {
        var db = [Float](repeating: 0, count: Self.bins)
        // Digital silence (a feed's lead-in, a gap in a saved clip) would drag the noise floor down so far that the
        // real audio after it saturates: draw it as background and leave the floor alone.
        guard bandsDB(frame, into: &db) else { for b in 0..<Self.bins { out[b] = 0 }; return }
        map(db, into: out)
    }

    /// Display levels for one column of band powers (dB), following and updating the noise floor.
    private func map(_ db: [Float], into out: UnsafeMutablePointer<UInt8>) {
        let span = SpectrogramStyle.shared.span
        for b in 0..<Self.bins {
            if warm < 30 { floorDB[b] = warm == 0 ? db[b] : min(floorDB[b], db[b]) + 0.3 }
            else { floorDB[b] += (db[b] - floorDB[b]) * (db[b] < floorDB[b] ? 0.03 : 0.003) }
        }
        warm += 1
        if config.fadeBackground {
            for b in 0..<Self.bins { out[b] = UInt8(min(max((db[b] - floorDB[b] - 4) / span, 0), 1) * 255) }
        } else {
            // One floor for every band: the quietest quarter of the band floors, so exposure still follows the room.
            let common = floorDB.sorted()[Self.bins / 4]
            for b in 0..<Self.bins { out[b] = UInt8(min(max((db[b] - common - 4) / span, 0), 1) * 255) }
        }
    }

    /// Mel band powers in dB for n samples at `frame`; false for digital silence.
    private func bandsDB(_ frame: UnsafePointer<Float>, into dbOut: inout [Float]) -> Bool {
        let n = self.n, half = n / 2, log2n = self.log2n
        var peak: Float = 0
        vDSP_maxmgv(frame, 1, &peak, vDSP_Length(n))
        if peak < 1e-7 { return false }
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, table.window, 1, &windowed, 1, vDSP_Length(n))
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { fb in
                    vDSP_ctoz(fb.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                ip[0] = 0                                   // imag[0] holds Nyquist; drop it
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        var bands = [Float](repeating: 0, count: Self.bins)
        vDSP_mmul(table.mel, 1, power, 1, &bands, 1, vDSP_Length(Self.bins), 1, vDSP_Length(half))
        for b in 0..<Self.bins { dbOut[b] = 10 * log10f(bands[b] + 1e-12) }
        return true
    }

    /// Whole-clip spectrogram (selections, saved clips): column-major levels, 128 per column.
    static func levels(of samples: [Float]) -> (data: [UInt8], columns: Int) {
        let dsp = SpectrogramDSP()
        let n = dsp.n
        guard samples.count >= n else { return ([], 0) }
        let cols = (samples.count - n) / hop + 1
        var data = [UInt8](repeating: 0, count: cols * bins)
        var dbs = [[Float]?](repeating: nil, count: cols)
        samples.withUnsafeBufferPointer { s in
            var db = [Float](repeating: 0, count: bins)
            for c in 0..<cols where dsp.bandsDB(s.baseAddress! + c * hop, into: &db) { dbs[c] = db }
        }
        // Start each band's floor at its quietest fifth over the whole clip, so the start isn't drawn bright while
        // the floor is still finding the background (or seeded too low by a fade-in); then it follows as live.
        let sounding = dbs.compactMap { $0 }
        guard !sounding.isEmpty else { return (data, cols) }
        var floors = (0..<bins).map { b -> Float in var v = sounding.map { $0[b] }; v.sort(); return v[v.count / 5] }
        // Bands far quieter than the rest (above a saved clip's AAC cutoff) would light up on any trace of energy.
        let median = floors.sorted()[bins / 2]
        floors = floors.map { max($0, median - 25) }
        for b in 0..<bins { dsp.floorDB[b] = floors[b] }
        dsp.warm = 30
        data.withUnsafeMutableBufferPointer { d in
            for c in 0..<cols { if let db = dbs[c] { dsp.map(db, into: d.baseAddress! + c * bins) } }
        }
        return (data, cols)
    }

    /// Image of columns `range` from column-major levels (low band at the bottom).
    static func image(_ levels: [UInt8], columns: Int, range: Range<Int>? = nil) -> CGImage? {
        let r = (range ?? 0..<columns).clamped(to: 0..<columns)
        guard !r.isEmpty else { return nil }
        let lut = SpectrogramStyle.shared.lut
        if SpectrogramStyle.shared.pixel { return pixelImage(levels, columns: columns, range: r, lut: lut) }
        let w = r.count, h = bins
        var px = [UInt32](repeating: lut[0], count: w * h)
        for x in 0..<w {
            let base = (r.lowerBound + x) * h
            for b in 0..<h { px[(h - 1 - b) * w + x] = lut[Int(levels[base + b])] }
        }
        return cgImage(&px, w, h)
    }

    /// 8-bit blocks: columns per block (about 7 blocks a second) and mel bands per block (SpectrogramStyle.pixelBands).
    static var pixelBlock: (columns: Int, bands: Int) { (14, SpectrogramStyle.shared.pixelBands) }

    /// Each block is the loudest level inside it, on absolute block numbers so blocks don't shimmer.
    private static func pixelImage(_ levels: [UInt8], columns: Int, range r: Range<Int>, lut: [UInt32]) -> CGImage? {
        let k = pixelBlock.columns, q = pixelBlock.bands
        let g0 = r.lowerBound / k, g1 = (r.upperBound + k - 1) / k
        let w = max(g1 - g0, 1), h = bins / q
        var px = [UInt32](repeating: lut[0], count: w * h)
        for x in 0..<w {
            for row in 0..<h {
                var m: UInt8 = 0
                for c in ((g0 + x) * k)..<min((g0 + x + 1) * k, columns) where c >= 0 {
                    let base = c * bins + row * q
                    for b in 0..<q where levels[base + b] > m { m = levels[base + b] }
                }
                px[(h - 1 - row) * w + x] = lut[Int(m)]
            }
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
    fileprivate static func melBank(n: Int, topHz: Float) -> [Float] {
        let half = n / 2, binHz = sr / Float(n)
        func mel(_ f: Float) -> Float { 2595 * log10f(1 + f / 700) }
        func hz(_ m: Float) -> Float { 700 * (powf(10, m / 2595) - 1) }
        let lo = mel(SpectrogramConfig.bottomHz), hi = mel(topHz)
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

    /// Center frequency of a mel band.
    static func bandHz(_ b: Int) -> Float {
        func mel(_ f: Float) -> Float { 2595 * log10f(1 + f / 700) }
        let lo = mel(SpectrogramConfig.bottomHz), hi = mel(SpectrogramStyle.shared.config.topHz), m = lo + (hi - lo) * Float(b + 1) / Float(bins + 1)
        return 700 * (powf(10, m / 2595) - 1)
    }

    /// Height fraction (0 = bottom) of a frequency on the display's mel axis.
    static func yFraction(hz: Float, topHz: Float = SpectrogramStyle.shared.config.topHz) -> CGFloat {
        func mel(_ f: Float) -> Float { 2595 * log10f(1 + f / 700) }
        return CGFloat((mel(hz) - mel(SpectrogramConfig.bottomHz)) / (mel(topHz) - mel(SpectrogramConfig.bottomHz)))
    }
}

/// Real-time scrolling spectrogram, separate from Perch. Fed on the audio thread, drawn at display rate.
/// The playhead trails the newest audio by about 200 ms so the mic's ~100 ms chunk bursts scroll smoothly.
final class LiveSpectrogram: @unchecked Sendable {
    static let maxSeconds = 30
    private static let bins = SpectrogramDSP.bins
    private static let capacity = maxSeconds * SpectrogramDSP.columnsPerSecond + 128
    private static let lag = 20.0             // columns (200 ms)

    private let lock = NSLock()
    private var dsp = SpectrogramDSP()
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
        tail = []; produced = 0; playhead = 0; lastDraw = 0; dsp = SpectrogramDSP()
        for i in ring.indices { ring[i] = 0 }
    }

    /// Audio thread: 32 kHz mono samples in, spectrogram columns out.
    func append(_ s: [Float]) {
        lock.lock(); defer { lock.unlock() }
        // Settings changed (FFT size, top frequency, background fade): new columns use them; what's already on
        // screen scrolls off as it was drawn.
        let want = SpectrogramStyle.shared.config
        if want != dsp.config { dsp = SpectrogramDSP(want) }
        let n = dsp.n
        tail += s
        var off = 0
        tail.withUnsafeBufferPointer { t in
            ring.withUnsafeMutableBufferPointer { r in
                while t.count - off >= n {
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

    struct Frame {
        let image: CGImage; let groups: Int; let fraction: CGFloat
        /// Raw columns per image column, and the absolute group number of the image's first column.
        let k: Int; let firstGroup: Int
        /// Where absolute spectrogram column `c` sits, as a fraction of the view width (can be < 0 or > 1).
        func x(ofColumn c: Int) -> CGFloat { (CGFloat(c) / CGFloat(k) - CGFloat(firstGroup) - fraction) / CGFloat(groups) }
    }

    /// Loudest spot (column, band) in the newest `seconds`, skipping rumble and bands near `avoiding`, for pinning a
    /// critter on the call that was just identified.
    func peak(seconds: Double, avoiding: [Int] = []) -> (column: Int, band: Int)? {
        lock.lock(); defer { lock.unlock() }
        let end = produced, start = max(end - Int(seconds * Double(SpectrogramDSP.columnsPerSecond)), end - Self.capacity + 1, 0)
        guard end - start > 10 else { return nil }
        var best = (c: start, b: 0, v: -1)
        for c in start..<end {
            let base = (c % Self.capacity) * Self.bins
            for b in 12..<(Self.bins - 1) where !avoiding.contains(where: { abs($0 - b) < 14 }) {
                let v = Int(ring[base + b - 1]) + 2 * Int(ring[base + b]) + Int(ring[base + b + 1])
                if v > best.v { best = (c, b, v) }
            }
        }
        return best.v < 0 ? nil : (best.c, best.b)
    }

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
        let pixel = SpectrogramStyle.shared.pixel
        // wider spans pool neighboring columns (max) down to the quality setting's image width
        let k = pixel ? SpectrogramDSP.pixelBlock.columns : max(1, Int((Double(visible) / Double(SpectrogramStyle.shared.quality.imageWidth)).rounded(.up)))
        let q = pixel ? SpectrogramDSP.pixelBlock.bands : 1
        let n = visible / k
        let pos = max(playhead, 0) / Double(k)
        let endGroup = Int(pos.rounded(.down))
        let w = n + 1, h = Self.bins / q
        let lut = SpectrogramStyle.shared.lut
        var px = [UInt32](repeating: lut[0], count: w * h)
        let bands = Self.bins
        var col = [UInt8](repeating: 0, count: bands)
        let oldest = produced - Self.capacity
        for x in 0..<w {
            let g = endGroup - n + x
            for b in 0..<bands { col[b] = 0 }
            var any = false
            for c in (g * k)..<(g * k + k) where c >= 0 && c > oldest && c < produced {
                let base = (c % Self.capacity) * bands
                for b in 0..<bands where ring[base + b] > col[b] { col[b] = ring[base + b] }
                any = true
            }
            guard any else { continue }
            for row in 0..<h {
                var m: UInt8 = 0
                for b in (row * q)..<(row * q + q) where col[b] > m { m = col[b] }
                px[(h - 1 - row) * w + x] = lut[Int(m)]
            }
        }
        guard let img = SpectrogramDSP.cgImage(&px, w, h) else { return nil }
        // 8-bit steps a whole block at a time, like an old handheld; otherwise it glides.
        return Frame(image: img, groups: n, fraction: pixel ? 0 : CGFloat(pos - Double(endGroup)), k: k, firstGroup: endGroup - n)
    }
}

struct SpectrogramView: View {
    let source: LiveSpectrogram
    let running: Bool
    var palette: SpectrogramPalette = .aurora
    var frequencyLabels = true
    /// Critters pinned on the calls they were identified from; they scroll with the audio.
    var markers: [Listener.Marker] = []
    /// Collect the critters that scroll off the left edge in a stack there (full screen).
    var dock = false
    var quality: SpectrogramQuality = .standard
    /// Top of the frequency axis (so the labels move when the setting does).
    var topHz: Float = 15_000
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / quality.framesPerSecond, paused: !running)) { tl in
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    palette.background
                    if let f = source.frame(now: tl.date.timeIntervalSinceReferenceDate) {
                        let colW = g.size.width / CGFloat(f.groups)
                        Image(decorative: f.image, scale: 1).resizable().interpolation(palette.isPixel ? .none : quality.interpolation)
                            .frame(width: g.size.width + colW, height: g.size.height)
                            .offset(x: -f.fraction * colW)
                        critters(f, g.size)
                    } else {
                        Text("Tap Listen to start").font(.callout).foregroundStyle(palette.labelColor)
                            .frame(width: g.size.width, height: g.size.height)
                    }
                }
                .clipped()
            }
        }
        .overlay(alignment: .leading) { if frequencyLabels { FrequencyAxis(color: palette.labelColor, pixel: palette.isPixel, topHz: topHz) } }
    }
}

extension SpectrogramView {
    @ViewBuilder fileprivate func critters(_ f: LiveSpectrogram.Frame, _ size: CGSize) -> some View {
        let wide = size.width > 560
        let placed = markers.map { ($0, f.x(ofColumn: $0.column) * size.width) }
        ForEach(placed.filter { $0.1 > -12 && $0.1 < size.width + 12 }, id: \.0.id) { m, x in
            let y = size.height * (1 - (CGFloat(m.band) + 0.5) / CGFloat(SpectrogramDSP.bins))
            CritterMarker(group: m.group, name: wide ? m.name : nil, pixel: palette.isPixel)
                .position(x: x, y: min(max(y - (wide ? 22 : 16), 16), size.height - 24))
                .transition(.scale(scale: 0.2).combined(with: .opacity))
        }
        .animation(.spring(duration: 0.35, bounce: 0.5), value: markers.count)
        if dock {
            // Passed off the left edge: newest first, one per species.
            let passed = placed.filter { $0.1 <= -12 }.sorted { $0.0.column > $1.0.column }
            var seen = Set<Int>()
            let shelf = passed.map(\.0).filter { seen.insert($0.index).inserted }.prefix(6)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(shelf)) { m in
                    HStack(spacing: 6) {
                        CritterMarker(group: m.group, name: nil, pixel: palette.isPixel)
                        Text(m.name).font(palette.isPixel ? .pixel(9) : .caption.weight(.semibold))
                            .foregroundStyle(.white).lineLimit(1)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.4), value: shelf.map(\.index))
            .padding(.leading, 36).padding(.top, 10)
            .allowsHitTesting(false)
        }
    }
}

/// A critter's group glyph on a tinted disc, pinned over the spectrogram.
struct CritterMarker: View {
    @Environment(\.theme) private var theme
    let group: TaxonGroup
    var name: String?
    var pixel = false
    var body: some View {
        VStack(spacing: 2) {
            Group {
                if pixel, let s = AppTheme.sprite(group) {
                    Image(s).interpolation(.none).resizable().scaledToFit().padding(2)
                } else {
                    Image(symbol: group.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
            }
                .frame(width: 24, height: 24)
                .background(pixel ? Color(hex: 0x1B1240) : theme.tint(group), in: pixel ? AnyShape(Rectangle()) : AnyShape(Circle()))
                .overlay { (pixel ? AnyShape(Rectangle()) : AnyShape(Circle())).stroke(.white.opacity(0.85), lineWidth: pixel ? 2 : 1.5) }
                .shadow(color: .black.opacity(0.4), radius: 3)
            if let name {
                Text(name).font(pixel ? .pixel(8) : .system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .allowsHitTesting(false)
    }
}

/// kHz ticks on the mel axis, so you can tell a 2 kHz owl from an 8 kHz warbler.
struct FrequencyAxis: View {
    var color: Color = .white.opacity(0.7)
    var pixel = false
    var topHz: Float = SpectrogramStyle.shared.config.topHz
    var body: some View {
        GeometryReader { g in
            // a low ceiling spreads the bottom out, so it gets a 500 Hz tick; ticks too near the top are dropped
            ForEach((topHz <= 6000 ? [500, 1000, 2000, 4000] : [1000, 2000, 4000, 8000]).filter { Float($0) <= topHz * 0.93 }, id: \.self) { hz in
                let y = g.size.height * (1 - SpectrogramDSP.yFraction(hz: Float(hz), topHz: topHz))
                HStack(spacing: 3) {
                    Rectangle().fill(color.opacity(0.6)).frame(width: 6, height: 1)
                    Text(hz < 1000 ? "\(hz)" : "\(hz / 1000)k").font(pixel ? .pixel(8) : .system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(color)
                }
                .position(x: 16, y: y)
            }
        }
        .allowsHitTesting(false)
    }
}
