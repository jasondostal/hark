import SwiftUI
import HarkCore

/// Touch-to-identify on the main spectrogram. The first touch freezes the last minute of audio (listening carries
/// on underneath), a drag selects a stretch (a tap grabs 5 s), and Perch scores exactly that stretch when you let go.
@MainActor
@Observable
final class Selection {
    static let sr = 32_000
    private(set) var clip: AudioSnapshot?
    private(set) var levels: (data: [UInt8], columns: Int)?
    private(set) var overview: CGImage?
    private(set) var viewImage: CGImage?
    /// Right edge of what's on screen, in samples of the snapshot. Starts where the live view was.
    private(set) var viewEnd = 0
    private(set) var viewLength = 10 * sr
    private(set) var range: Range<Int> = 0..<0
    private(set) var result: DetectionPolicy.Triage?
    private(set) var analyzing = false
    private(set) var logged: Set<Int> = []

    var isFrozen: Bool { clip != nil }
    var total: Int { clip?.samples.count ?? 0 }
    var viewStart: Int { viewEnd - viewLength }
    /// The snapshot is longer than the screen, so there's more to scroll back to.
    var canPan: Bool { total > viewLength + Self.sr }

    func freeze(_ clip: AudioSnapshot, seconds: Int, lagSamples: Int) {
        ClipPlayer.shared.stop()
        self.clip = clip; levels = nil; overview = nil; viewImage = nil
        viewLength = seconds * Self.sr
        viewEnd = max(clip.samples.count - lagSamples, 1)
        range = 0..<0; result = nil; logged = []
        let s = clip.samples, id = clip.id
        Task {
            let lv = await Task.detached(priority: .userInitiated) { SpectrogramDSP.levels(of: s) }.value
            guard self.clip?.id == id else { return }
            levels = lv
            overview = SpectrogramDSP.image(lv.data, columns: lv.columns)
            renderView()
        }
    }

    func unfreeze() {
        ClipPlayer.shared.stop()
        clip = nil; levels = nil; overview = nil; viewImage = nil; result = nil; range = 0..<0; analyzing = false
    }

    /// Overview strip: center the screen on this fraction of the snapshot.
    func pan(toFraction f: CGFloat) {
        let c = Int(min(max(f, 0), 1) * CGFloat(total))
        let end = min(max(c + viewLength / 2, min(viewLength, total)), total)
        guard end != viewEnd else { return }
        viewEnd = end
        renderView()
    }

    private func renderView() {
        guard let levels else { return }
        let lo = max(viewStart, 0) / SpectrogramDSP.hop, hi = viewEnd / SpectrogramDSP.hop
        viewImage = SpectrogramDSP.image(levels.data, columns: levels.columns, range: lo..<hi)
    }

    func x(of sample: Int, width: CGFloat) -> CGFloat {
        CGFloat(sample - viewStart) / CGFloat(viewLength) * width
    }

    func sample(atX x: CGFloat, width: CGFloat) -> Int {
        let s = viewStart + Int((x / max(width, 1)) * CGFloat(viewLength))
        return min(max(s, 0), total)
    }

    /// Drag: select between two samples (at least 1 s).
    func select(_ a: Int, _ b: Int) { set(min(a, b)..<max(a, b)) }

    /// Tap: 5 s centered on the tap.
    func grab(around c: Int) {
        let half = 5 * Self.sr / 2
        let lo = min(max(c - half, 0), max(total - 2 * half, 0))
        set(lo..<min(lo + 2 * half, total))
    }

    private func set(_ r: Range<Int>) {
        var r = r.clamped(to: 0..<total)
        if r.count < Self.sr {
            let c = (r.lowerBound + r.upperBound) / 2
            let lo = min(max(c - Self.sr / 2, 0), max(total - Self.sr, 0))
            r = lo..<min(lo + Self.sr, total)
        }
        if r != range { range = r; result = nil; logged = []; ClipPlayer.shared.stop() }
    }

    var selectedSamples: [Float] { clip.map { Array($0.samples[range]) } ?? [] }

    /// What Perch actually scores: the selection, or for a short one the 5 s of real audio around it. Padding a
    /// short selection with silence wrecks the scores (a 1 s cardinal: 21% padded, 88% with its surroundings).
    var scoredRange: Range<Int> {
        let w = 5 * Self.sr
        guard range.count < w, total > range.count else { return range }
        let c = (range.lowerBound + range.upperBound) / 2
        let lo = min(max(c - w / 2, 0), max(total - w, 0))
        return lo..<min(lo + w, total)
    }
    var isWidened: Bool { scoredRange != range }
    private var scoredSamples: [Float] { clip.map { Array($0.samples[scoredRange]) } ?? [] }
    var playID: String { "selection-\(clip?.id.uuidString ?? "")-\(range.lowerBound)-\(range.upperBound)" }

    func analyze(_ listener: Listener) async {
        guard !analyzing, result == nil, !range.isEmpty else { return }
        analyzing = true
        let r = range
        let out = await listener.analyze(scoredSamples)
        analyzing = false
        if range == r, isFrozen { result = out }      // ignore if the selection moved while scoring
        else if isFrozen { await analyze(listener) }
    }

    func log(_ i: Int, _ p: Float, confirmed: Bool, _ listener: Listener) {
        guard let clip, !range.isEmpty else { return }
        listener.logSelection(i, confidence: p, samples: scoredSamples, at: clip.time(atSample: range.lowerBound), confirmed: confirmed)
        logged.insert(i)
    }

    /// Loudest band in the selection (levels are already over the noise floor, so steady hum doesn't win).
    var peakHz: Float? {
        guard let levels, !range.isEmpty else { return nil }
        let lo = range.lowerBound / SpectrogramDSP.hop, hi = min(range.upperBound / SpectrogramDSP.hop, levels.columns)
        guard hi > lo else { return nil }
        var sums = [Int](repeating: 0, count: SpectrogramDSP.bins)
        for c in lo..<hi { let base = c * SpectrogramDSP.bins; for b in 0..<SpectrogramDSP.bins { sums[b] += Int(levels.data[base + b]) } }
        guard let (b, total) = sums.enumerated().max(by: { $0.element < $1.element }), total > (hi - lo) * 8 else { return nil }
        return SpectrogramDSP.bandHz(b)
    }

    var caption: String {
        guard let clip, !range.isEmpty else { return "" }
        return "\(String(format: "%.1f", Double(range.count) / Double(Self.sr))) s · \(clip.time(atSample: range.lowerBound).formatted(date: .omitted, time: .standard))"
    }
}

/// The frozen spectrogram: what was on screen, with the selection lit and the rest dimmed.
struct FrozenSpectrogram: View {
    let selection: Selection
    var palette: SpectrogramPalette = .aurora
    var frequencyLabels = true
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let x = { (s: Int) -> CGFloat in min(max(CGFloat(s - selection.viewStart) / CGFloat(selection.viewLength) * w, 0), w) }
            ZStack(alignment: .topLeading) {
                palette.background
                if let img = selection.viewImage {
                    let x0 = x(0)
                    Image(decorative: img, scale: 1).resizable().interpolation(SpectrogramStyle.shared.pixel ? .none : .medium)
                        .frame(width: w - x0, height: h).offset(x: x0)
                } else {
                    ProgressView().tint(palette.labelColor).frame(width: w, height: h)
                }
                if !selection.range.isEmpty {
                    let a = x(selection.range.lowerBound), b = x(selection.range.upperBound)
                    let ca = x(selection.scoredRange.lowerBound), cb = x(selection.scoredRange.upperBound)
                    let edge = palette == .paper ? Color.accentColor : palette.overlayTint
                    // dim what Perch didn't hear; the context a short selection is scored with gets a lighter dim
                    Color.black.opacity(0.55).frame(width: ca, height: h)
                    Color.black.opacity(0.55).frame(width: w - cb, height: h).offset(x: cb)
                    Color.black.opacity(0.25).frame(width: max(a - ca, 0), height: h).offset(x: ca)
                    Color.black.opacity(0.25).frame(width: max(cb - b, 0), height: h).offset(x: b)
                    // light up the selection itself
                    Group {
                        if palette == .paper { Color.accentColor.opacity(0.14) }
                        else { palette.overlayTint.opacity(0.22).blendMode(.screen) }
                    }
                    .frame(width: max(b - a, 2), height: h).offset(x: a)
                    ForEach([a, b], id: \.self) { ex in
                        Rectangle().fill(edge).frame(width: 2, height: h).offset(x: ex - 1)
                        Capsule().fill(edge).frame(width: 8, height: 34).offset(x: ex - 4, y: h / 2 - 17)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                    }
                }
            }
            .clipped()
        }
        .overlay(alignment: .leading) { if frequencyLabels { FrequencyAxis(color: palette.labelColor, pixel: palette.isPixel) } }
    }
}

/// The whole frozen minute in a thin strip; drag it to look further back.
struct SelectionOverview: View {
    let selection: Selection
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, t = CGFloat(max(selection.total, 1))
            let v0 = CGFloat(max(selection.viewStart, 0)) / t * w, v1 = CGFloat(selection.viewEnd) / t * w
            ZStack(alignment: .topLeading) {
                Color.black
                if let o = selection.overview { Image(decorative: o, scale: 1).resizable().interpolation(SpectrogramStyle.shared.pixel ? .none : .medium) }
                Color.black.opacity(0.55).frame(width: v0, height: h)
                Color.black.opacity(0.55).frame(width: max(w - v1, 0), height: h).offset(x: v1)
                RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1.5).frame(width: max(v1 - v0, 4), height: h - 1).offset(x: v0, y: 0.5)
                if !selection.range.isEmpty {
                    let a = CGFloat(selection.range.lowerBound) / t * w, b = CGFloat(selection.range.upperBound) / t * w
                    Rectangle().fill(.yellow).frame(width: max(b - a, 2), height: 3).offset(x: a, y: h - 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.35)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in selection.pan(toFraction: v.location.x / w) })
        }
        .frame(height: 30)
        .accessibilityLabel("Last minute overview. Drag to look further back.")
    }
}

/// Results for the selection, shown at the top of the list while the spectrogram is frozen.
struct SelectionSection: View {
    @Environment(Listener.self) private var listener
    let selection: Selection
    var body: some View {
        Section {
            if selection.range.isEmpty {
                Text("Drag across a call to identify it, or tap to grab 5 seconds.").foregroundStyle(.secondary)
            } else {
                SelectionStats(selection: selection)
            }
            if !selection.range.isEmpty && selection.analyzing {
                HStack(spacing: 10) { ProgressView(); Text("Identifying…").foregroundStyle(.secondary) }
            }
            if let t = selection.result, !selection.analyzing {
                if t.hits.isEmpty && t.unusual.isEmpty && t.maybes.isEmpty {
                    Text("Nothing identified here. Try selecting the whole call, or a clearer one.").foregroundStyle(.secondary)
                }
                ForEach(t.hits, id: \.index) { h in row(h.index, h.confidence, kind: nil) }
                ForEach(t.unusual, id: \.index) { h in row(h.index, h.confidence, kind: listener.unusualReason(h.index)) }
                ForEach(t.maybes, id: \.index) { h in row(h.index, h.confidence, kind: "maybe") }
            }
        } header: { Text("Selection") } footer: {
            if selection.isWidened && !selection.range.isEmpty {
                Text("Short selections are scored with the 5 seconds around them; Perch needs the context.")
            }
        }
    }

    @ViewBuilder private func row(_ i: Int, _ p: Float, kind: String?) -> some View {
        if let l = listener.label(i) {
            VStack(alignment: .leading, spacing: 6) {
                NowRow(label: l, confidence: p, agreed: selection.result?.agreed.contains(i) == true)
                if let kind {
                    Text(kind).font(.caption).foregroundStyle(kind == "maybe" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }
                if l.group.isSpecies {
                    if selection.logged.contains(i) {
                        Label("Logged", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                    } else {
                        HStack {
                            Button("Log") { selection.log(i, p, confirmed: false, listener) }.buttonStyle(.bordered)
                            Button { selection.log(i, p, confirmed: true, listener) } label: { Label("I saw it", systemImage: "eye") }
                                .buttonStyle(.bordered).tint(.green)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}

/// What you selected, at a glance: how long, when (and how long ago), and the loudest pitch in it.
struct SelectionStats: View {
    let selection: Selection
    var body: some View {
        if let clip = selection.clip {
            let r = selection.range
            let start = clip.time(atSample: r.lowerBound), end = clip.time(atSample: r.upperBound)
            HStack(alignment: .top, spacing: 0) {
                stat("Length", String(format: "%.1f s", Double(r.count) / Double(Selection.sr)), nil)
                Divider().padding(.horizontal, 10)
                stat("Heard", start.formatted(date: .omitted, time: .standard),
                     "to \(end.formatted(date: .omitted, time: .standard)) · \(ago(start))")
                Divider().padding(.horizontal, 10)
                stat("Peak", selection.peakHz.map { $0 >= 1000 ? String(format: "%.1f kHz", $0 / 1000) : "\(Int($0)) Hz" } ?? "—", nil)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func stat(_ label: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            if let sub { Text(sub).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7) }
        }
        .frame(maxWidth: label == "Heard" ? .infinity : nil, alignment: .leading)
    }
    private func ago(_ d: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(d)))
        return s < 60 ? "\(s) s ago" : "\(s / 60) min ago"
    }
}
