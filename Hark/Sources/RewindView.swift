import SwiftUI
import HarkCore

/// Rewind: the last minute as a spectrogram. Drag across the overview to select a stretch (tap = 5 s around
/// the tap), see it zoomed, play it, and ask Perch what's in exactly that stretch.
struct RewindView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    let clip: RewindClip

    @State private var levels: (data: [UInt8], columns: Int)?
    @State private var overview: CGImage?
    @State private var sel: Range<Int> = 0..<0          // in samples
    @State private var dragStart: Int?
    @State private var result: DetectionPolicy.Triage?
    @State private var analyzing = false
    @State private var logged: Set<Int> = []
    private var player: ClipPlayer { ClipPlayer.shared }

    private static let sr = 32_000
    private var total: Int { clip.samples.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    overviewStrip.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                    detail.listRowInsets(EdgeInsets())
                    controls
                } footer: {
                    Text("Drag across the strip to select, or tap to grab 5 seconds. Analyze scores exactly the selection.")
                }
                if let result { results(result) }
            }
            .navigationTitle("Rewind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { player.stop(); dismiss() } } }
            .task {
                sel = max(0, total - 5 * Self.sr)..<total
                let s = clip.samples
                let lv = await Task.detached(priority: .userInitiated) { SpectrogramDSP.levels(of: s) }.value
                levels = lv
                overview = SpectrogramDSP.image(lv.data, columns: lv.columns)
                await analyze()
            }
        }
    }

    // MARK: Overview (whole minute)

    private var overviewStrip: some View {
        VStack(spacing: 2) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    Color.black
                    if let overview { Image(decorative: overview, scale: 1).resizable().interpolation(.medium) }
                    // dim outside the selection
                    let x0 = w * CGFloat(sel.lowerBound) / CGFloat(max(total, 1))
                    let x1 = w * CGFloat(sel.upperBound) / CGFloat(max(total, 1))
                    Color.black.opacity(0.55).frame(width: max(x0, 0))
                    Color.black.opacity(0.55).frame(width: max(w - x1, 0)).offset(x: x1)
                    RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 2)
                        .frame(width: max(x1 - x0, 2)).offset(x: x0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let a = sample(at: v.startLocation.x, width: w), b = sample(at: v.location.x, width: w)
                    if abs(v.translation.width) > 6 { setSelection(min(a, b)..<max(a, b)) }
                }.onEnded { v in
                    if abs(v.translation.width) <= 6 {   // tap: 5 s centered on the tap
                        let c = sample(at: v.location.x, width: w), half = 5 * Self.sr / 2
                        let lo = min(max(c - half, 0), max(total - 2 * half, 0))
                        setSelection(lo..<min(lo + 2 * half, total))
                    }
                    Task { await analyze() }
                })
            }
            .frame(height: 64)
            HStack {
                Text("−\(Int(clip.duration.rounded())) s"); Spacer(); Text("−\(Int((clip.duration / 2).rounded())) s"); Spacer(); Text("now")
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func sample(at x: CGFloat, width: CGFloat) -> Int {
        Int((min(max(x / max(width, 1), 0), 1) * CGFloat(total)).rounded())
    }

    private func setSelection(_ r: Range<Int>) {
        var r = r
        if r.count < Self.sr {                            // at least 1 s
            let c = (r.lowerBound + r.upperBound) / 2
            let lo = min(max(c - Self.sr / 2, 0), max(total - Self.sr, 0))
            r = lo..<min(lo + Self.sr, total)
        }
        if r != sel { sel = r; result = nil; logged = [] }
    }

    // MARK: Detail (the selection, zoomed)

    private var detail: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let levels, let img = SpectrogramDSP.image(levels.data, columns: levels.columns,
                                                         range: (sel.lowerBound / SpectrogramDSP.hop)..<(sel.upperBound / SpectrogramDSP.hop)) {
                Image(decorative: img, scale: 1).resizable().interpolation(.medium)
            }
            Text("\(String(format: "%.1f", Double(sel.count) / Double(Self.sr))) s · \(clip.time(atSample: sel.lowerBound).formatted(date: .omitted, time: .standard))")
                .font(.caption2.monospacedDigit()).padding(6).foregroundStyle(.white.opacity(0.8))
        }
        .frame(height: 170)
    }

    private var controls: some View {
        HStack {
            let id = "rewind-\(sel.lowerBound)-\(sel.upperBound)"
            Button {
                player.toggle(id: id, samples: Array(clip.samples[sel]))
            } label: {
                Label(player.playingID == id ? "Stop" : "Play", systemImage: player.playingID == id ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button { Task { await analyze() } } label: {
                if analyzing { ProgressView().frame(maxWidth: .infinity) }
                else { Label("Analyze", systemImage: "waveform.badge.magnifyingglass").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(analyzing || result != nil)
        }
        .padding(.vertical, 4)
    }

    private func analyze() async {
        guard !analyzing, result == nil, !sel.isEmpty else { return }
        analyzing = true
        let r = sel
        result = await listener.analyze(Array(clip.samples[r]))
        analyzing = false
        if sel != r { result = nil }                       // selection moved while scoring
    }

    // MARK: Results

    @ViewBuilder private func results(_ t: DetectionPolicy.Triage) -> some View {
        Section("In this selection") {
            if t.hits.isEmpty && t.unusual.isEmpty && t.maybes.isEmpty {
                Text("Nothing identified. Try a tighter selection around the call.").foregroundStyle(.secondary)
            }
            ForEach(t.hits, id: \.index) { h in row(h.index, h.confidence, kind: nil) }
            ForEach(t.unusual, id: \.index) { h in row(h.index, h.confidence, kind: "unusual here") }
            ForEach(t.maybes, id: \.index) { h in row(h.index, h.confidence, kind: "maybe") }
        }
    }

    @ViewBuilder private func row(_ i: Int, _ p: Float, kind: String?) -> some View {
        if let l = listener.label(i) {
            VStack(alignment: .leading, spacing: 6) {
                NowRow(label: l, confidence: p)
                if let kind {
                    Text(kind).font(.caption).foregroundStyle(kind == "maybe" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }
                if l.group.isSpecies {
                    if logged.contains(i) {
                        Label("Logged", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                    } else {
                        HStack {
                            Button("Log") { log(i, p, confirmed: false) }.buttonStyle(.bordered)
                            Button { log(i, p, confirmed: true) } label: { Label("I saw it", systemImage: "eye") }
                                .buttonStyle(.bordered).tint(.green)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func log(_ i: Int, _ p: Float, confirmed: Bool) {
        listener.logSelection(i, confidence: p, samples: Array(clip.samples[sel]),
                              at: clip.time(atSample: sel.lowerBound), confirmed: confirmed)
        logged.insert(i)
    }
}
