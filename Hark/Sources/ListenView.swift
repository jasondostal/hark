import SwiftUI
import SwiftData
import TipKit
import HarkCore

/// Home: a big live spectrogram on top, what's being heard in the middle, and a camera-style bar at the bottom
/// (Log · Listen · Settings) where the thumb already is.
struct ListenView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.modelContext) private var ctx
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("-settings")   // screenshot aids
    @State private var showLog = ProcessInfo.processInfo.arguments.contains("-logtab")
    /// Which selection edge a drag grabbed (nil = drawing a new selection); decided when the drag starts.
    @State private var dragEdge: Int?
    @State private var dragStarted = false

    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.theme) private var theme
    private var landscape: Bool { verticalSize == .compact }
    /// Landscape full screen: the list column hides so the spectrogram spans the phone. It comes back while a
    /// selection is open, since that's where the results are.
    @AppStorage("landscapeFull") private var fullScreen = false
    private var showColumn: Bool { !fullScreen || selection.isFrozen }
    /// Portrait full screen: by the expand button, or because Settings > Spectrogram > Height is all the way up.
    /// The list comes back while a selection is open, as in landscape.
    @AppStorage("portraitFull") private var portraitFull = false
    private var heightIsFull: Bool { listener.spectrogramHeight >= 0.97 }
    private var portraitIsFull: Bool { (portraitFull || heightIsFull) && !selection.isFrozen }
    /// The spectrogram has the screen to itself right now.
    private var fullNow: Bool { landscape ? !showColumn : portraitIsFull }
    @State private var showFiles = ProcessInfo.processInfo.arguments.contains("-files")   // screenshot aid
    /// A session to open the Log on (a finished point count, an analyzed file).
    @State private var logSession: UUID?

    var body: some View {
        @Bindable var listener = listener
        layout
        .background(.appBackground)
        .environment(\.compactRows, landscape)
        .animation(.spring, value: listener.celebration?.id)
        .sheet(isPresented: $showSettings) { SettingsView().themeRoot() }
        .sheet(isPresented: $showLog, onDismiss: { logSession = nil }) { LogView(openSession: logSession).themeRoot() }
        .sheet(isPresented: $showFiles) {
            FileAnalysisView().themeRoot()
        }
        .onChange(of: listener.state) { _, s in
            if s == .listening { listener.selection.unfreeze() }
        }
        .onChange(of: FileAnalysis.shared.arrivals) { _, _ in showSettings = false; showLog = false; filesChosen = true; showFiles = true }
        .onChange(of: selection.isFrozen) { _, frozen in
            if !frozen { HearTip.hasSelection = false }
        }
        .onChange(of: selection.range) { _, r in
            guard !r.isEmpty else { return }
            HearTip.hasSelection = true
            Task { await ModeTip.selected.donate() }
        }
        .onAppear {
            listener.modelContext = ctx
            WidgetBridge.refresh(ctx, listening: listener.state == .listening, now: true)
            #if DEBUG
            Task { await DemoData.seedIfRequested(ctx) }      // screenshot aid: -demolog <dir>
            #endif
        }
    }

    /// Portrait: spectrogram on top, list, thumb bar. Landscape (phone on its side, a tripod, a dash): the spectrogram
    /// takes the width and shows twice the time, the list is a column beside it and the buttons a camera-style rail.
    @ViewBuilder private var layout: some View {
        if landscape {
            GeometryReader { g in
                // Portrait width of this phone = the landscape height including the safe areas.
                let portraitWidth = g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom
                HStack(spacing: 0) {
                    spectrogramPanel(height: nil)
                        .background(listener.palette.background.ignoresSafeArea())   // no white gutters by the island
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { w in
                            listener.widthScale = w / max(portraitWidth, 1)
                        }
                        .overlay(alignment: .bottom) { if !showColumn { celebration.padding(.bottom, 70) } }
                    if showColumn {
                        list
                            .frame(width: 270)
                            .overlay(alignment: .bottom) { celebration.padding(.bottom, 16) }
                            .transition(.move(edge: .trailing))
                    }
                    sideRail
                }
                .animation(.snappy, value: showColumn)
            }
            .onDisappear { listener.widthScale = 1 }
        } else {
            GeometryReader { g in
                // A selection needs room for its results, however tall the spectrogram is set.
                let share = selection.isFrozen ? min(listener.spectrogramHeight, 0.45) : listener.spectrogramHeight
                VStack(spacing: 0) {
                    spectrogramPanel(height: portraitIsFull ? nil : max(140, g.size.height * share))
                    if !portraitIsFull { list.transition(.move(edge: .bottom)) }
                }
                .animation(.snappy, value: portraitIsFull)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .overlay(alignment: .bottom) { celebration.padding(.bottom, 120) }
            .onAppear { listener.widthScale = 1 }
        }
    }

    private var list: some View {
        List { Group { content }.themedRows() }
            .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 12) }
            .listStyle(.insetGrouped)
            .themedList()
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.horizontal, landscape ? 8 : nil, for: .scrollContent)
            .listSectionSpacing(landscape ? .compact : .default)
    }

    // MARK: Spectrogram

    private var selection: Selection { listener.selection }

    /// Live, it scrolls; the first touch freezes it (listening carries on) and a drag picks out a call.
    private func spectrogramPanel(height: CGFloat?) -> some View {
        GeometryReader { g in
            Group {
                if selection.isFrozen {
                    FrozenSpectrogram(selection: selection, palette: listener.palette, frequencyLabels: listener.frequencyLabels, topHz: Float(listener.topKHz * 1000))
                } else {
                    SpectrogramView(source: listener.live, running: listener.state == .listening,
                                    palette: listener.palette, frequencyLabels: listener.frequencyLabels,
                                    markers: listener.critters ? listener.markers : [],
                                    dock: listener.critters && fullNow,
                                    quality: listener.quality, topHz: Float(listener.topKHz * 1000))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in touchMoved(v, width: g.size.width) }
                .onEnded { v in touchEnded(v, width: g.size.width) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(selection.isFrozen ? "Paused spectrogram" : "Spectrogram")
            .accessibilityHint("Touch and drag across a call to identify it.")
            .accessibilityAction(named: "Identify the last 5 seconds") {
                guard listener.canSelect else { return }
                listener.freezeForSelection()
                selection.grab(around: max(selection.viewEnd - 5 * Selection.sr / 2, 0))
                Task { await selection.analyze(listener) }
            }
        }
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { SpectrogramStyle.shared.set(panelHeight: $0) }
        .overlay(alignment: .top) {
            if selection.isFrozen && selection.canPan {
                SelectionOverview(selection: selection).padding(.horizontal, 12).padding(.top, 8)
            }
        }
        .overlay(alignment: .topLeading) { if fullNow && !listener.critters { hearingTags } }
        .overlay(alignment: .bottom) { selection.isFrozen ? AnyView(frozenControls) : AnyView(liveControls) }
    }

    private func touchMoved(_ v: DragGesture.Value, width: CGFloat) {
        if !dragStarted {
            dragStarted = true
            dragEdge = nil
            if selection.isFrozen && !selection.range.isEmpty {   // started on an edge: adjust it instead
                let a = selection.x(of: selection.range.lowerBound, width: width)
                let b = selection.x(of: selection.range.upperBound, width: width)
                let da = abs(v.startLocation.x - a), db = abs(v.startLocation.x - b)
                if min(da, db) < 24 { dragEdge = da <= db ? 0 : 1 }
            }
        }
        if !selection.isFrozen {
            guard listener.canSelect else { return }
            listener.freezeForSelection()
        }
        guard selection.isFrozen else { return }
        let here = selection.sample(atX: v.location.x, width: width)
        switch dragEdge {
        case 0: if abs(v.translation.width) > 2 { selection.select(here, selection.range.upperBound) }
        case 1: if abs(v.translation.width) > 2 { selection.select(selection.range.lowerBound, here) }
        default:
            guard abs(v.translation.width) > 6 else { return }
            selection.select(selection.sample(atX: v.startLocation.x, width: width), here)
        }
    }

    private func touchEnded(_ v: DragGesture.Value, width: CGFloat) {
        defer { dragStarted = false; dragEdge = nil }
        guard selection.isFrozen else { return }
        if abs(v.translation.width) <= 6 && dragEdge == nil { selection.grab(around: selection.sample(atX: v.location.x, width: width)) }
        Task { await selection.analyze(listener) }
    }

    private var overlayTint: Color { listener.palette.overlayTint }
    private var overlayShade: LinearGradient {
        LinearGradient(colors: [.clear, .black.opacity(listener.palette == .paper ? 0 : 0.45)], startPoint: .top, endPoint: .bottom)
    }

    private var liveControls: some View {
        @Bindable var listener = listener
        let listening = listener.state == .listening
        return HStack(spacing: 10) {
            Spacer(minLength: 0)
            if listening, let end = listener.endsAt {
                // Point count: time left
                Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                    .font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(listener.palette.labelColor)
                    .accessibilityLabel("Time left in the point count")
            }
            if listening, listener.showSpeed, listener.lastInferenceMs > 0, listener.autoID {
                Label(String(format: "%.0f ms", listener.lastInferenceMs), systemImage: "bolt.fill")
                    .labelStyle(.titleAndIcon).font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(listener.palette.labelColor).lineLimit(1).fixedSize()
                    .accessibilityLabel(String(format: "Last check took %.0f milliseconds", listener.lastInferenceMs))
            }
            if listener.state == .listening {
                Image(systemName: "mic.fill").font(.caption).foregroundStyle(listener.palette.labelColor)
                LevelBar(db: listener.levelDB, color: listener.palette == .owling ? listener.palette.overlayTint : .green).frame(width: listener.endsAt == nil && !listener.showSpeed ? 70 : 40)
                    .accessibilityLabel("Microphone level")
            }
            if landscape || !heightIsFull {
                let full = landscape ? fullScreen : portraitFull
                Button { if landscape { fullScreen.toggle() } else { portraitFull.toggle() } } label: {
                    Image(systemName: full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(overlayTint)
                .accessibilityLabel(full ? "Show the list" : "Full screen spectrogram")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(overlayShade.allowsHitTesting(false))
    }

    private var frozenControls: some View {
        HStack(spacing: 10) {
            Button { selection.unfreeze() } label: {
                Label("Back to live", systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 4).padding(.vertical, 4)
                    .fixedSize()
            }
            .buttonStyle(.bordered)
            .tint(overlayTint)
            Text(selection.range.isEmpty ? "Paused · drag across a call" : selection.caption)
                .font(.caption.monospacedDigit()).foregroundStyle(listener.palette.labelColor)
                .lineLimit(1).minimumScaleFactor(0.6)
                .allowsHitTesting(false)
            Spacer(minLength: 0)
            if !selection.range.isEmpty {
                let player = ClipPlayer.shared
                let playing = player.playingID == selection.playID
                Button {
                    player.toggle(id: selection.playID, samples: selection.selectedSamples)
                    HearTip().invalidate(reason: .actionPerformed)
                } label: {
                    Label(playing ? "Stop" : "Hear it", systemImage: playing ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4).padding(.vertical, 4)
                        .fixedSize()
                }
                .buttonStyle(.bordered)
                .tint(overlayTint)
                .popoverTip(HearTip(), arrowEdge: .bottom)
                .accessibilityLabel(playing ? "Stop playback" : "Hear the selection")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(overlayShade.allowsHitTesting(false))
    }

    // MARK: Hearing now / this session

    @ViewBuilder private var content: some View {
        switch listener.state {
        case .loading:
            Section { HStack(spacing: 10) { ProgressView(); Text("Setting up the models on this iPhone. Only after installing or updating; a few seconds.").font(.callout) } }
        case .failed(let msg):
            Section { Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
        default:
            if listener.perchPending {
                Section { HStack(spacing: 10) { ProgressView(); Text("Perch is still setting up; listening with BirdNET+ until it joins.").font(.callout).foregroundStyle(.secondary) } }
            }
        }
        if selection.isFrozen { SelectionSection(selection: selection) }
        let active = listener.state == .listening || !listener.session.isEmpty || !listener.manual.isEmpty
        if !active && listener.state == .ready && !selection.isFrozen && choice == .live {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hear something?").font(.title3.bold())
                    Tip(symbol: "mic.fill", text: "Tap the **green button**. Birds, frogs, insects and mammals show up here as Hark hears them.")
                    Tip(symbol: "hand.draw", text: "Missed it? **Touch the spectrogram** to pause it, then drag across the call. It reaches back a full minute.")
                    Tip(symbol: "square.grid.2x2", text: "The row above the button picks what it does: a timed **point count**, a walked **survey**, or audio **recordings**.")
                }
                .padding(.vertical, 6)
            }
        }
        if let done = listener.finishedCount, listener.state != .listening, !selection.isFrozen {
            Section {
                Button { logSession = done.session; showLog = true } label: {
                    Label("\(done.species) species. See the tally", systemImage: "checklist")
                }
            } header: { Text("Point count done").themedHeader() }
        }
        if listener.state == .ready && choice != .live && !selection.isFrozen {
            Section {
                Label(choice.hint, systemImage: choice.symbol).font(.callout).foregroundStyle(.secondary)
                if choice == .point {
                    Picker("Count for", selection: Binding(get: { listener.pointMinutes }, set: { listener.pointMinutes = $0 })) {
                        ForEach([3, 5, 10, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
            } header: { Text(choice.title).themedHeader() }
        }
        if active && !listener.autoID && listener.state == .listening && !selection.isFrozen {
            Section {
                Label("Hark only identifies what you pick. Touch the spectrogram and drag across a call.", systemImage: "hand.draw")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Manual mode").themedHeader() }
        }
        if active && listener.autoID {
            Section {
                if listener.micStalled {
                    Label("Something else has the microphone. Hark picks up again as soon as it's free.", systemImage: "mic.slash")
                        .font(.caption).foregroundStyle(.orange)
                }
                if listener.guardActive {
                    Label("Hearing people or music: only IDs Hark is very sure of count right now", systemImage: "person.wave.2")
                        .font(.caption).foregroundStyle(.orange)
                }
                if listener.hearingNow.isEmpty && listener.maybes.isEmpty && !listener.micStalled {
                    Text(listener.state == .listening ? "Listening…" : "Stopped").foregroundStyle(.secondary)
                }
                ForEach(listener.hearingNow) { o in
                    if let l = listener.label(o.index) { NowRow(label: l, confidence: o.bestConfidence, agreed: listener.agreed.contains(o.index))
                            .muteSwipe(o.index, detection: listener.detection(for: o)) }
                }
                ForEach(listener.maybes) { m in
                    if let l = listener.label(m.index) { MaybeRow(label: l, maybe: m).muteSwipe(m.index, maybe: m) }
                }
            } header: { Text("Hearing now").themedHeader() }
        }
        if !listener.session.isEmpty || !listener.manual.isEmpty {
            Section {
                ForEach(listener.manual) { d in
                    if let i = listener.labels?.index(ofScientific: d.scientific) { ManualRow(detection: d).muteSwipe(i, detection: d) } else { ManualRow(detection: d) }
                }
                ForEach(listener.session) { o in
                    if let l = listener.label(o.index) {
                        SessionRow(label: l, occurrence: o, detection: listener.detection(for: o))
                            .muteSwipe(o.index, detection: listener.detection(for: o))
                    }
                }
            } header: { Text("This session").themedHeader() }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
            ModeStrip(choice: choiceBinding, locked: listener.state == .listening)
            HStack(alignment: .center) {
                BarButton(title: "Log", symbol: "list.bullet.rectangle.portrait") { showLog = true }
                Spacer()
                ListenButton(choice: choice) { showFiles = true }
                Spacer()
                BarButton(title: "Settings", symbol: "slider.horizontal.3") { showSettings = true }
            }
            .padding(.horizontal, 30)
        }
        .padding(.top, 8).padding(.bottom, 2)
        .background(.appBar)
    }

    /// What the big button does, as one choice (the camera's row of modes): the listening mode, Manual folded in
    /// as its own entry, and Recordings, which isn't listening at all.
    @State private var filesChosen = false
    private var choice: ModeChoice {
        if listener.state == .listening {
            return listener.activeMode == .point ? .point : listener.activeMode == .survey ? .survey : listener.idMode == .manual ? .manual : .live
        }
        if filesChosen { return .files }
        return listener.mode == .point ? .point : listener.mode == .survey ? .survey : listener.idMode == .manual ? .manual : .live
    }
    private var choiceBinding: Binding<ModeChoice> {
        Binding(get: { choice }, set: { c in
            filesChosen = c == .files
            switch c {
            case .live: listener.mode = .live; listener.idMode = .auto
            case .manual: listener.mode = .live; listener.idMode = .manual
            case .point: listener.mode = .point
            case .survey: listener.mode = .survey
            case .files: break
            }
        })
    }

    /// Full screen: what's calling right now, as small tags over the old (left) end of the spectrogram.
    private var hearingTags: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(listener.autoID ? Array(listener.hearingNow.prefix(4)) : []) { o in
                if let l = listener.label(o.index) {
                    HStack(spacing: 6) {
                        Image(symbol: l.group.symbol).font(.caption)
                        Text(l.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if listener.agreed.contains(o.index) {
                            Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.good)
                        }
                        Text("\(o.bestConfidence.shownPercent)%").font(.caption.monospacedDigit()).opacity(0.75)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, listener.palette == .paper ? .light : .dark)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .animation(.snappy, value: listener.hearingNow.map(\.index))
        .padding(.leading, 44).padding(.top, 10)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hearing now")
    }

    /// Landscape: the same three buttons, top to bottom, on the trailing edge where the right thumb is.
    private var sideRail: some View {
        VStack {
            BarButton(title: "Settings", symbol: "slider.horizontal.3") { showSettings = true }
            Spacer(minLength: 0)
            ModeStrip(choice: choiceBinding, locked: listener.state == .listening, vertical: true)
            ListenButton(choice: choice) { showFiles = true }
            Spacer(minLength: 0)
            BarButton(title: "Log", symbol: "list.bullet.rectangle.portrait") { showLog = true }
        }
        .padding(.vertical, 8)
        .frame(width: 96)
        .frame(maxHeight: .infinity)
        .background(.appBar)
    }

    @ViewBuilder private var celebration: some View {
        if let c = listener.celebration {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.celebrate)
                VStack(alignment: .leading) {
                    Text("New for you!").font(.caption.weight(.bold)).foregroundStyle(.celebrate)
                    Text(c.name).speciesName(.headline)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct Tip: View {
    let symbol: String
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// The shutter-style Listen / Stop button.
/// What the big button does. Listening modes, plus Recordings (analyze files instead of the microphone).
enum ModeChoice: String, CaseIterable, Identifiable {
    case live, manual, point, survey, files
    var id: String { rawValue }
    var title: String {
        switch self { case .live: "Live"; case .manual: "Manual"; case .point: "Point count"; case .survey: "Survey"; case .files: "Recordings" }
    }
    /// On the big button, so it says what a press will do.
    var symbol: String {
        switch self { case .live: "mic.fill"; case .manual: "hand.draw.fill"; case .point: "timer"; case .survey: "figure.walk"; case .files: "folder.fill" }
    }
    var hint: String {
        switch self {
        case .live: "Identifies everything it hears, for as long as you like."
        case .manual: "Listens without identifying. Touch the spectrogram and drag across a call to identify just that."
        case .point: "Stay in one spot for a set time; Hark tallies every species heard there."
        case .survey: "Walk a route; Hark maps it and what you heard along the way. Runs until you stop it."
        case .files: "Identify what's in audio files: a recorder's card, a voice memo, a video."
        }
    }
}

/// The row of modes above the big button, like the camera's. Tap one; the button's icon changes to match.
/// While listening it shows the mode that's running and can't be changed.
struct ModeStrip: View {
    @Binding var choice: ModeChoice
    var locked = false
    var vertical = false
    @Environment(\.theme) private var theme
    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 1)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(ModeChoice.allCases) { c in
                let on = c == choice
                Button { withAnimation(.snappy) { choice = c } } label: {
                    Text(c.title)
                        .font(theme.isPixel ? .pixel(vertical ? 8 : 9) : .system(size: vertical ? 11 : 13, weight: on ? .bold : .medium))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, vertical ? 6 : 9).padding(.vertical, vertical ? 3 : 5)
                        .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .background { if on { Capsule().fill(.tint.opacity(0.14)) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(locked && !on ? 0.3 : 1)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)       // a fixed row, like the system tab bar
        .disabled(locked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }
}

struct ListenButton: View {
    @Environment(Listener.self) private var listener
    @Environment(\.theme) private var theme
    var choice: ModeChoice = .live
    /// Recordings: the button opens the file analysis instead of the microphone.
    var files: () -> Void = {}
    var body: some View {
        let listening = listener.state == .listening
        let style = ListenStyle(theme: theme, listening: listening)
        Button { if choice == .files && !listening { files() } else { Task { await listener.toggle() } } } label: {
            ZStack {
                if theme.isPixel {   // a chunky square key with a hard drop shadow
                    Rectangle().fill(style.shadow).frame(width: 62, height: 62).offset(x: 5, y: 5)
                    Rectangle().fill(style.fill).frame(width: 62, height: 62)
                        .overlay { Rectangle().stroke(style.ring, lineWidth: 3) }
                } else {
                    Circle().stroke(style.ring, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(style.fill).frame(width: 66, height: 66)
                        .shadow(color: style.glow ?? .clear, radius: style.glow == nil ? 0 : 14)
                }
                if listener.state == .loading {
                    ProgressView().tint(style.glyph)
                } else {
                    Image(systemName: listening ? "stop.fill" : choice.symbol)
                        .font(.system(size: listening ? 24 : 27, weight: .semibold)).foregroundStyle(style.glyph)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 80, height: 80)
            .animation(.snappy, value: listening)
        }
        .buttonStyle(.plain)
        .disabled(listener.state == .loading)
        .accessibilityLabel(listening ? "Stop listening" : choice == .files ? "Analyze recordings" : "Start listening, \(choice.title)")
        .sensoryFeedback(.impact(weight: .medium), trigger: listening)
    }
}

private struct BarButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.title2).frame(height: 28)
                Text(title).font(.caption2.weight(.medium)).lineLimit(1)
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)       // like the system tab bar: labels stop growing
            .frame(width: 76, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

// MARK: Rows

struct NowRow: View {
    let label: HarkCore.Label
    let confidence: Float
    /// Both models backed it (Both mode).
    var agreed = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.compactRows) private var compact
    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    /// Landscape column: name, a seal when both models agree, and the percentage.
    private var compactBody: some View {
        HStack(spacing: 10) {
            TaxonIcon(group: label.group)
            SpeciesTitle(common: label.common, scientific: label.scientific, species: label.group.isSpecies, style: .headline).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            if agreed {
                Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.good)
                    .accessibilityLabel("Perch and BirdNET+ agree")
            }
            Text("\(confidence.shownPercent)%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var fullBody: some View {
        HStack(spacing: 12) {
            TaxonIcon(group: label.group)
            VStack(alignment: .leading) {
                SpeciesTitle(common: label.common, scientific: label.scientific, species: label.group.isSpecies, style: .headline)
                SpeciesSubtitle(common: label.common, scientific: label.scientific, species: label.group.isSpecies)
                if agreed {
                    Label("Both models", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.good)
                        .accessibilityLabel("Perch and BirdNET+ agree")
                }
                if typeSize.isAccessibilitySize { ConfidenceBar(value: confidence) }   // big text: bar under the name
            }
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize { ConfidenceBar(value: confidence) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Not logged automatically; one tap logs it or logs it as seen.
/// Maybe = plausible but under the threshold (faint, "?"). Unusual = confident but never recorded near you (orange).
struct MaybeRow: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dynamicTypeSize) private var typeSize
    let label: HarkCore.Label
    let maybe: Maybe
    var body: some View {
        HStack(spacing: 12) {
            TaxonIcon(group: label.group, faint: !maybe.unusual)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: maybe.unusual ? "exclamationmark.circle.fill" : "questionmark.circle.fill")
                        .font(.caption).foregroundStyle(.white, maybe.unusual ? Color.orange : Color.gray)
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading) {
                Text(maybe.unusual ? label.displayName : "\(label.displayName)?")
                    .foregroundStyle(maybe.unusual ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                Text("\(maybe.unusual ? listener.unusualReason(maybe.index) : "maybe") · \(maybe.best.shownPercent)%")
                    .font(.caption).foregroundStyle(maybe.unusual ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                if typeSize.isAccessibilitySize { HStack { buttons } }
            }
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        Button("Log it") { listener.logMaybe(maybe, confirmed: false) }
            .buttonStyle(.bordered).fixedSize()
        Button { listener.logMaybe(maybe, confirmed: true) } label: { Image(systemName: "eye") }
            .buttonStyle(.bordered).tint(GoodStyle()).accessibilityLabel("I saw it")
    }
}

struct ManualRow: View {
    let detection: Detection
    var body: some View {
        HStack(spacing: 12) {
            TaxonIcon(group: detection.taxon)
            VStack(alignment: .leading) {
                HStack(spacing: 6) { SpeciesTitle(common: detection.common, scientific: detection.scientific, species: detection.isSpecies); if detection.isFirst { NewBadge() } }
                SpeciesSubtitle(common: detection.common, scientific: detection.scientific, species: detection.isSpecies, row: true)
                Text("\(detection.firstHeard.formatted(date: .omitted, time: .shortened)) · logged by hand · \(detection.confidence.shownPercent)%")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ConfirmButton(detection: detection)
        }
    }
}

struct SessionRow: View {
    let label: HarkCore.Label
    let occurrence: DetectionTracker.Occurrence
    let detection: Detection?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var subtitle: String {
        var s = "\(occurrence.firstHeard.formatted(date: .omitted, time: .shortened)) · \(occurrence.bestConfidence.shownPercent)%"
        let mins = Int(occurrence.lastHeard.timeIntervalSince(occurrence.firstHeard) / 60)
        if mins >= 1 { s += " · \(mins) min" }
        return s
    }
    var body: some View {
        HStack(spacing: 12) {
            TaxonIcon(group: label.group)
            VStack(alignment: .leading) {
                HStack(spacing: 6) { SpeciesTitle(common: label.common, scientific: label.scientific, species: label.group.isSpecies); if detection?.isFirst == true { NewBadge() } }
                SpeciesSubtitle(common: label.common, scientific: label.scientific, species: label.group.isSpecies, row: true)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                if typeSize.isAccessibilitySize, let d = detection { ConfirmButton(detection: d) }
            }
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize, let d = detection { ConfirmButton(detection: d) }
        }
    }
}

extension EnvironmentValues {
    /// Narrow landscape column: rows drop secondary detail and buttons go icon-only.
    @Entry var compactRows = false
}

struct ConfirmButton: View {
    @Bindable var detection: Detection
    @Environment(\.compactRows) private var compact
    var body: some View {
        Button { detection.confirmed.toggle() } label: {
            Label(detection.confirmed ? "Saw it" : "I saw it",
                  systemImage: detection.confirmed ? "checkmark.seal.fill" : "eye")
                .font(.caption)
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        }
        .buttonStyle(.bordered)
        .tint(detection.confirmed ? AnyShapeStyle(.good) : AnyShapeStyle(.secondary))
    }
}

struct ConfidenceBar: View {
    let value: Float
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.tint).frame(width: g.size.width * CGFloat(Fusion.display(value)))
                }
            }
            .frame(width: 56, height: 6)
            Text("\(value.shownPercent)%").font(.caption.monospacedDigit()).fixedSize().frame(minWidth: 36, alignment: .trailing)
        }
    }
}

struct LevelBar: View {
    let db: Float
    var color: Color = .green
    var body: some View {
        let v = CGFloat(min(max((db + 80) / 70, 0), 1))
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(color.gradient).frame(width: g.size.width * v)
            }
        }
        .frame(height: 5)
        .animation(.linear(duration: 0.1), value: v)
    }
}

extension View {
    /// Swipe left: "Not it" (wrong this time), or "Never show" this species.
    func muteSwipe(_ index: Int, detection: Detection? = nil, maybe: Maybe? = nil) -> some View {
        modifier(MuteSwipe(index: index, detection: detection, maybe: maybe))
    }
}

/// Swipe left to never show a species; long-press for everything you can do with it.
private struct MuteSwipe: ViewModifier {
    @Environment(Listener.self) private var listener
    let index: Int
    var detection: Detection?
    var maybe: Maybe?
    @State private var sharing: Detection?
    func body(content: Content) -> some View {
        content
            .sheet(item: $sharing) { d in ShareCardSheet(detection: d).themeRoot() }
            .swipeActions(edge: .trailing) {
                // Full swipe = Not it (this time only); muting for good is the second, deliberate button.
                Button(role: .destructive) { withAnimation { listener.notIt(index) } } label: { Label("Not it", systemImage: "xmark") }
                Button { listener.mute(index) } label: { Label("Never show", systemImage: "speaker.slash") }.tint(.gray)
            }
            .contextMenu {
                if let m = maybe {
                    Button { listener.logMaybe(m, confirmed: false) } label: { Label("Log it", systemImage: "plus") }
                    Button { listener.logMaybe(m, confirmed: true) } label: { Label("I saw it", systemImage: "eye") }
                }
                if let d = detection {
                    Button { d.confirmed.toggle() } label: {
                        Label(d.confirmed ? "I didn't see it" : "I saw it", systemImage: d.confirmed ? "eye.slash" : "eye")
                    }
                    Button { sharing = d } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                }
                if let url = listener.lookupURL(index) {
                    Link(destination: url) { Label("Look it up on iNaturalist", systemImage: "safari") }
                }
                Divider()
                Button(role: .destructive) { withAnimation { listener.notIt(index) } } label: {
                    Label("Not it (just this time)", systemImage: "xmark")
                }
                Button(role: .destructive) { listener.mute(index) } label: { Label("Never show this species", systemImage: "speaker.slash") }
            }
    }
}

/// Lets a view switch label styles at run time.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
