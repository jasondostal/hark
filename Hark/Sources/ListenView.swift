import SwiftUI
import SwiftData
import TipKit
import HarkCore

/// Home: a big live spectrogram on top, what's being heard in the middle, and a camera-style bar at the bottom
/// (Journal · Listen · Settings) where the thumb already is. It's all one surface: the list and the bar are drawn
/// straight on the look's background, and the picture melts into it.
struct ListenView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.modelContext) private var ctx
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("-settings")   // screenshot aids
    @State private var showLog = ProcessInfo.processInfo.arguments.contains("-logtab")
    /// Which selection edge a drag grabbed (nil = drawing a new selection); decided when the drag starts.
    @State private var dragEdge: Int?
    @State private var dragStarted = false

    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.theme) private var theme
    /// The look's colors: what the list and the bar are drawn in when the picture doesn't have the whole screen.
    @Environment(\.surface) private var look
    /// The picture's own colors: everything drawn over it, and the bar and rail in full screen.
    private var stage: Surface { theme.stage(listener.palette) }
    private var landscape: Bool { verticalSize == .compact }
    /// On its side the spectrogram always has the screen, with captions over it. A column comes in beside it only
    /// while a selection is open, since that's where its results are.
    private var showColumn: Bool { selection.isFrozen }
    /// Portrait full screen: by the expand button, or because Settings > Spectrogram > Height is all the way up.
    /// The list comes back while a selection is open, as in landscape.
    @AppStorage("portraitFull") private var portraitFull = false
    private var heightIsFull: Bool { listener.spectrogramHeight >= 0.97 }
    private var portraitIsFull: Bool { (portraitFull || heightIsFull) && !selection.isFrozen }
    /// The spectrogram has the screen to itself right now.
    private var fullNow: Bool { landscape ? !showColumn : portraitIsFull }
    @State private var showFiles = ProcessInfo.processInfo.arguments.contains("-files")   // screenshot aid
    /// A session to open the Journal on (a finished point count, an analyzed file).
    @State private var logSession: UUID?
    /// A detection tapped in the list: its page, right here.
    @State private var opened: Detection?
    /// "What's new", once, for someone updating.
    @State private var showNews = false

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
        .sheet(item: $opened) { DetectionSheet(detection: $0).themeRoot() }
        .sheet(isPresented: $showNews) { WhatsNewView().themeRoot() }
        .onChange(of: listener.state) { _, s in
            if s == .listening { listener.selection.unfreeze() }
        }
        .onChange(of: FileAnalysis.shared.arrivals) { _, _ in showSettings = false; showLog = false; showNews = false; opened = nil; filesChosen = true; showFiles = true }
        .onChange(of: selection.isFrozen) { _, frozen in
            if !frozen { HearTip.hasSelection = false }
        }
        .onChange(of: selection.range) { _, r in
            guard !r.isEmpty else { return }
            HearTip.hasSelection = true
        }
        .onAppear {
            listener.modelContext = ctx
            WidgetBridge.refresh(ctx, listening: listener.state == .listening, now: true)
            if !showSettings && !showLog && !showFiles && WhatsNew.isDue() { showNews = true }
            #if DEBUG
            Task {
                await DemoData.seedIfRequested(ctx)      // screenshot aid: -demolog <dir>
                if ProcessInfo.processInfo.arguments.contains("-opendetection") {      // screenshot aid: a detection's page over Listen
                    var f = FetchDescriptor<Detection>(sortBy: [SortDescriptor(\.firstHeard, order: .reverse)]); f.fetchLimit = 1
                    opened = try? ctx.fetch(f).first
                }
            }
            #endif
        }
    }

    /// Portrait: spectrogram on top, list, thumb bar. Landscape (phone on its side, a tripod, a dash): the spectrogram
    /// takes the width and shows twice the time, with captions over it and the buttons on a camera-style rail.
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
                    if showColumn {
                        list
                            .frame(width: 280)
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
                let top = g.safeAreaInsets.top
                VStack(spacing: 0) {
                    // The picture runs up under the status bar (which steps aside in full screen).
                    spectrogramPanel(height: portraitIsFull ? nil : max(140, (g.size.height - top) * share) + top, topInset: top)
                    if !portraitIsFull { list.transition(.move(edge: .bottom)) }
                }
                .animation(.snappy, value: portraitIsFull)
            }
            .ignoresSafeArea(.container, edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .overlay(alignment: .bottom) { if !portraitIsFull { celebration.padding(.bottom, 120) } }   // full screen says it in the caption
            .statusBarHidden(portraitIsFull)
            .onAppear { listener.widthScale = 1 }
        }
    }

    /// Rows straight on the surface: no cards, no rules, the way captions sit on the picture.
    private var list: some View {
        List {
            Group { content }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: landscape ? 12 : 18, bottom: 5, trailing: landscape ? 12 : 16))
        }
        .environment(\.openDetection) { opened = $0 }
        .environment(\.defaultMinListRowHeight, 1)
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 12) }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 6, for: .scrollContent)
        .contentMargins(.bottom, 16, for: .scrollContent)
    }

    // MARK: Spectrogram

    private var selection: Selection { listener.selection }

    /// Live, it scrolls; the first touch freezes it (listening carries on) and a drag picks out a call.
    private func spectrogramPanel(height: CGFloat?, topInset: CGFloat = 0) -> some View {
        GeometryReader { g in
            Group {
                if selection.isFrozen {
                    FrozenSpectrogram(selection: selection, palette: listener.palette, frequencyLabels: listener.frequencyLabels, topHz: Float(listener.topKHz * 1000))
                } else {
                    SpectrogramView(source: listener.live, running: listener.state == .listening,
                                    palette: listener.palette, frequencyLabels: listener.frequencyLabels,
                                    markers: listener.critters ? listener.markers : [],
                                    stage: fullNow, topInset: topInset,
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
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
            SpectrogramStyle.shared.set(panelHeight: size.height)
            // Taller than wide (full screen upright): zoom in on time by the same amount, so calls keep their shape.
            listener.tallScale = size.height > size.width && !selection.isFrozen ? Double(size.width / size.height) : 1
        }
        .overlay(alignment: .top) {
            if selection.isFrozen && selection.canPan {
                SelectionOverview(selection: selection).padding(.horizontal, 12).padding(.top, 8)
            }
        }
        .overlay(alignment: landscape ? .trailing : .bottom) {
            // The picture melts into what's next to it (the list, the bar, the rail) instead of stopping at it.
            let bg = fullNow ? stage.background : look.background
            LinearGradient(colors: [bg.opacity(0), bg], startPoint: landscape ? .leading : .top, endPoint: landscape ? .trailing : .bottom)
                .frame(width: landscape ? 14 : nil, height: landscape ? nil : fullNow ? 18 : 30)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) {
            if fullNow && landscape {      // and out of the gutter beside the island
                let bg = stage.background
                LinearGradient(colors: [bg, bg.opacity(0)], startPoint: .leading, endPoint: .trailing).frame(width: 22).allowsHitTesting(false)
            }
        }
        .overlay {
            if fullNow {      // full screen: what's calling, as captions in the corner
                Color.clear.overlay(alignment: .topLeading) {
                    CaptionFeed(compact: landscape, more: { logSession = listener.sessionID; showLog = true }, notes: AnyView(stageNotes))
                        .environment(\.openDetection) { opened = $0 }
                        .padding(.top, topInset + 12).padding(.leading, listener.frequencyLabels ? 46 : 16).padding(.trailing, 16)
                }
                .clipped()
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { if fullNow { UndoToast().padding(.bottom, 14) } }      // "Not it" from a caption
        .overlay(alignment: .bottom) { selection.isFrozen ? AnyView(frozenControls) : AnyView(liveControls) }
        .environment(\.surface, stage)
        .environment(\.colorScheme, stage.scheme)
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
            // (The microphone level is the Listen button's ring.)
            if !landscape && !heightIsFull {
                Button { portraitFull.toggle() } label: {
                    Image(systemName: portraitFull ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(GlassCircle())
                .accessibilityLabel(portraitFull ? "Show the list" : "Full screen spectrogram")
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, fullNow ? 10 : 16)
    }

    private var frozenControls: some View {
        HStack(spacing: 10) {
            Button { selection.unfreeze() } label: {
                Label("Back to live", systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 4).padding(.vertical, 4)
                    .fixedSize()
            }
            .buttonStyle(SurfaceChip())
            if selection.range.isEmpty {      // once there's a selection, its numbers are in the list below
                Text("Paused · drag across a call")
                    .font(.caption).foregroundStyle(listener.palette.labelColor)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .allowsHitTesting(false)
            }
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
                .buttonStyle(SurfaceChip(tint: stage.accent))
                .popoverTip(HearTip(), arrowEdge: .bottom)
                .accessibilityLabel(playing ? "Stop playback" : "Hear the selection")
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 16)
    }

    // MARK: Hearing now / this session

    @ViewBuilder private var content: some View {
        switch listener.state {
        case .loading:
            HStack(spacing: 10) { ProgressView(); Text("Setting up the models on this iPhone. Only after installing or updating; a few seconds.").font(.callout) }
                .surfacePanel()
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 10) {
                Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                if listener.micDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Button { UIApplication.shared.open(url) } label: { Label("Open Settings to turn it on", systemImage: "gear") }
                        .buttonStyle(SurfaceChip(tint: look.accent))
                    SurfaceNote("In Settings, switch on Microphone, then come back and tap the button.")
                }
            }
            .surfacePanel()
        default:
            if listener.perchPending {
                HStack(spacing: 10) { ProgressView(); Text("Perch is still setting up; listening with BirdNET+ until it joins.").font(.callout).foregroundStyle(.secondary) }
                    .surfacePanel()
            }
        }
        if FileAnalysis.shared.running {
            let jobs = FileAnalysis.shared.jobs
            let left = jobs.filter { if case .waiting = $0.state { true } else if case .running = $0.state { true } else { false } }.count
            Button { showFiles = true } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(left == 1 ? "Analyzing a recording" : "Analyzing recordings, \(left) to go").font(.callout.weight(.medium))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    SurfaceNote("Hark can't listen until it's done: the models do one thing at a time. Tap to watch it or stop it.")
                }
                .surfacePanel()
            }
            .buttonStyle(.plain)
        }
        if selection.isFrozen { SelectionSection(selection: selection) }
        let active = listener.state == .listening || !listener.session.isEmpty || !listener.manual.isEmpty
        if !active && listener.state == .ready && !selection.isFrozen && choice == .live {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hear something?").font(theme.captionFont(30)).padding(.bottom, 2)
                Tip(symbol: "mic.fill", text: "Tap the **big button**. Birds, frogs, insects and mammals show up here as Hark hears them.")
                Tip(symbol: "hand.draw", text: "Missed it? **Touch the spectrogram** to pause it, then drag across the call. It reaches back a full minute.")
                Tip(symbol: "chevron.up.chevron.down", text: "**Live** above the button is the mode. Tap it for a timed **point count**, a walked **survey**, or audio **recordings**.")
            }
            .padding(.top, 14)
        }
        if let done = listener.finished, listener.state != .listening, !selection.isFrozen {
            SurfaceHeader(done.mode == .point ? (done.complete ? "Point count done" : "Point count stopped") : done.mode == .survey ? "Survey done" : "Stopped listening")
            Button { logSession = done.session; showLog = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: done.mode == .point ? "checklist" : done.mode == .survey ? "map" : "book.pages")
                        .font(.body.weight(.semibold)).foregroundStyle(.accent).frame(width: 26)
                    Text("\(done.species) species. \(done.mode == .point ? "See the tally" : done.mode == .survey ? "See the route" : "See the session")")
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .surfacePanel()
            }
            .buttonStyle(.plain)
        }
        if listener.state == .ready && choice != .live && !selection.isFrozen {
            SurfaceHeader(choice.title)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: choice.symbol).foregroundStyle(.accent).frame(width: 26)
                    Text(choice.hint).font(.callout).foregroundStyle(.secondary)
                }
                if choice == .point {
                    HStack {
                        Text("Count for").font(.callout.weight(.medium))
                        Spacer(minLength: 0)
                        Picker("Count for", selection: Binding(get: { listener.pointMinutes }, set: { listener.pointMinutes = $0 })) {
                            ForEach([3, 5, 10, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                        }
                        .pickerStyle(.menu).labelsHidden()
                    }
                    .padding(.leading, 38)
                }
            }
            .surfacePanel()
        }
        if active && !listener.autoID && listener.state == .listening && !selection.isFrozen {
            SurfaceHeader("Manual mode")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "hand.draw").foregroundStyle(.accent).frame(width: 26)
                Text("Hark only identifies what you pick. Touch the spectrogram and drag across a call.").font(.callout).foregroundStyle(.secondary)
            }
            .surfacePanel()
        }
        if active && listener.autoID && listener.state == .listening {
            // Notices sit beside the title, so they come and go without pushing the list around.
            SurfaceHeader("Hearing now") {
                Group {
                    if listener.micStalled {
                        Label("Mic in use elsewhere", systemImage: "mic.slash").labelStyle(.titleAndIcon)
                            .accessibilityLabel("Something else has the microphone")
                    } else if listener.guardActive {
                        Label("People or music: sure IDs only", systemImage: "person.wave.2").labelStyle(.titleAndIcon)
                            .accessibilityLabel("Hearing people or music: only IDs Hark is very sure of count right now")
                    }
                }
                .font(.caption.weight(.medium)).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.8)
            }
            .animation(.default, value: listener.guardActive)
            if listener.hearingNow.isEmpty && listener.maybes.isEmpty {
                // one row either way, so nothing below it moves
                if listener.micStalled {
                    Label("Something else has the microphone. Hark picks up again when it's free.", systemImage: "mic.slash")
                        .font(.callout).foregroundStyle(.orange).frame(minHeight: 50)
                } else {
                    ListeningRow()
                }
            }
            ForEach(listener.hearingNow) { o in
                if let l = listener.label(o.index) {
                    let d = listener.detection(for: o)
                    NowRow(label: l, confidence: o.bestConfidence, agreed: listener.agreed.contains(o.index), detection: d)
                        .muteSwipe(o.index, detection: d)
                }
            }
            ForEach(listener.maybes) { m in
                if let l = listener.label(m.index) { MaybeRow(label: l, maybe: m).muteSwipe(m.index, maybe: m) }
            }
        }
        if !listener.session.isEmpty || !listener.manual.isEmpty {
            SurfaceHeader("This session") {
                let n = Set(listener.session.map(\.index)).count + listener.manual.count
                Text("\(n) species").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(look.ink.opacity(0.45))
            }
            ForEach(listener.manual) { d in
                if let i = listener.labels?.index(ofScientific: d.scientific) { ManualRow(detection: d).muteSwipe(i, detection: d) } else { ManualRow(detection: d) }
            }
            ForEach(listener.session) { o in
                if let l = listener.label(o.index) {
                    SessionRow(label: l, occurrence: o, detection: listener.detection(for: o))
                        .muteSwipe(o.index, detection: listener.detection(for: o))
                }
            }
        }
    }

    /// Full screen has no list, so what the list would say besides species goes over the picture, above the captions:
    /// the first-run line, trouble with the microphone, a mode that needs setting up.
    @ViewBuilder private var stageNotes: some View {
        let listening = listener.state == .listening
        if case .failed(let msg) = listener.state {
            VStack(alignment: .leading, spacing: 8) {
                StageNote(symbol: "exclamationmark.triangle.fill", text: msg, color: .red)
                if listener.micDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Button { UIApplication.shared.open(url) } label: { Label("Open Settings to turn it on", systemImage: "gear") }
                        .buttonStyle(SurfaceChip())
                }
            }
        } else if listener.state == .loading {
            StageNote(symbol: "hourglass", text: "Setting up the models on this iPhone. A few seconds.")
        } else if FileAnalysis.shared.running {
            Button { showFiles = true } label: { Label("Analyzing recordings. Hark can't listen until it's done", systemImage: "folder") }
                .buttonStyle(SurfaceChip())
        } else if listening && listener.micStalled {
            StageNote(symbol: "mic.slash.fill", text: "Something else has the microphone. Hark picks up again when it's free.", color: .orange)
        } else if listening && listener.guardActive && listener.autoID {
            StageNote(symbol: "person.wave.2.fill", text: "People or music: sure IDs only", color: .orange)
        } else if listening && !listener.autoID {
            StageNote(symbol: "hand.draw.fill", text: "Manual: touch the picture and drag across a call.")
        } else if !listening && listener.state == .ready && choice == .point {
            Picker("Count for", selection: Binding(get: { listener.pointMinutes }, set: { listener.pointMinutes = $0 })) {
                ForEach([3, 5, 10, 15, 20, 30], id: \.self) { Text("Count for \($0) min").tag($0) }
            }
            .pickerStyle(.menu).tint(stage.ink).font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 2).frame(height: 32)
            .background { Capsule().fill(.ultraThinMaterial) }
            .overlay { Capsule().strokeBorder(stage.ink.opacity(0.28), lineWidth: 1) }
        } else if !listening && listener.state == .ready && listener.session.isEmpty && listener.manual.isEmpty && choice == .live {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hear something?").font(theme.captionFont(landscape ? 22 : 26))
                Text("Tap the big button. Touch the picture to pick out a call.").font(.system(size: 13, weight: .medium)).opacity(0.75)
            }
            .foregroundStyle(stage.ink)
            .shadow(color: stage.background.opacity(0.9), radius: 7).shadow(color: stage.background.opacity(0.7), radius: 1.5)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        // Full screen: the bar sits on the spectrogram's own darkness, in its ink. Otherwise on the look's.
        let surface = portraitIsFull ? stage : look
        return VStack(spacing: 6) {
            ModeButton(choice: choiceBinding, running: listener.state == .listening ? listener.startedAt : nil)
            HStack(alignment: .center) {
                BarButton(title: "Journal", symbol: "book.pages") { showLog = true }
                Spacer()
                ListenButton(choice: choice) { showFiles = true }
                Spacer()
                BarButton(title: "Settings", symbol: "slider.horizontal.3") { showSettings = true }
            }
            .padding(.horizontal, 30)
        }
        .padding(.top, 8).padding(.bottom, 2)
        .background(surface.bar)
        .environment(\.surface, surface)
        .environment(\.colorScheme, surface.scheme)
        .animation(.snappy, value: portraitIsFull)
    }

    /// What the big button does, as one choice (the mode button above it): the listening mode, Manual folded in
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

    /// Landscape: the same three buttons, top to bottom, on the trailing edge where the right thumb is.
    private var sideRail: some View {
        let surface = fullNow ? stage : look
        return VStack {
            BarButton(title: "Settings", symbol: "slider.horizontal.3") { showSettings = true }
            Spacer(minLength: 0)
            ModeButton(choice: choiceBinding, running: listener.state == .listening ? listener.startedAt : nil, narrow: true)
            ListenButton(choice: choice) { showFiles = true }
            Spacer(minLength: 0)
            BarButton(title: "Journal", symbol: "book.pages") { showLog = true }
        }
        .padding(.vertical, 8)
        .frame(width: 104)      // room for the longest mode name ("Point count") with a margin
        .frame(maxHeight: .infinity)
        .background(surface.bar)
        .environment(\.surface, surface)
        .environment(\.colorScheme, surface.scheme)
        .animation(.snappy, value: fullNow)
    }

    @ViewBuilder private var celebration: some View {
        if let c = listener.celebration {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.celebrate)
                VStack(alignment: .leading) {
                    Text("New for you!").font(.caption.weight(.bold)).foregroundStyle(.celebrate)
                    Text(c.name).font(theme.captionFont(19))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(look.ink.opacity(0.18), lineWidth: 1) }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct Tip: View {
    let symbol: String
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(.accent).frame(width: 26)
            Text(text).font(.callout).foregroundStyle(.ink.opacity(0.72))
        }
    }
}

/// A section's name, straight on the surface, with room beside it for a count or a notice.
struct SurfaceHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) { self.title = title; self.trailing = trailing() }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).themedHeader().foregroundStyle(.ink.opacity(0.55)).lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.top, 12)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small print under something on the surface.
struct SurfaceNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(.ink.opacity(0.5)).fixedSize(horizontal: false, vertical: true) }
}

/// A quiet panel on the surface, for notes and the few rows that aren't a species.
private struct SurfacePanel: ViewModifier {
    @Environment(\.surface) private var surface
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        let shape = theme.isPixel ? AnyShape(Rectangle()) : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        content
            .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface.ink.opacity(0.07), in: shape)
            .overlay { shape.stroke(surface.ink.opacity(0.1), lineWidth: 1) }
            .contentShape(Rectangle())
    }
}
extension View {
    func surfacePanel() -> some View { modifier(SurfacePanel()) }
}

/// One line over the picture in full screen: what the list's notices say when there's no list.
struct StageNote: View {
    let symbol: String
    let text: String
    var color: Color?
    @Environment(\.surface) private var surface
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13, weight: .semibold)).foregroundStyle(color ?? surface.ink)
        .shadow(color: surface.background.opacity(0.9), radius: 6).shadow(color: surface.background.opacity(0.7), radius: 1.5)
        .accessibilityElement(children: .combine)
    }
}

/// "Listening…", as tall as the row that will take its place.
private struct ListeningRow: View {
    @Environment(\.surface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform").font(.system(size: 18, weight: .semibold)).foregroundStyle(surface.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                .frame(width: 48, height: 48)
            Text("Listening…").font(.callout).foregroundStyle(surface.ink.opacity(0.55))
        }
        .frame(minHeight: 50)
        .accessibilityElement(children: .combine)
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
    /// One line, in the list of modes.
    var brief: String {
        switch self {
        case .live: "Identify everything it hears"
        case .manual: "Identify only the calls you pick"
        case .point: "One spot, a set time, a tally"
        case .survey: "A walk, with a map of what you heard"
        case .files: "Identify audio files"
        }
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

/// The mode, as one small button above the big one: it names what a press will do, and a tap lists the modes.
/// While listening it names the mode that's running and how long it has been, and can't be changed.
struct ModeButton: View {
    @Binding var choice: ModeChoice
    /// Listening since (nil when idle).
    var running: Date?
    /// The landscape rail: narrower, and the running time goes under the name.
    var narrow = false
    @Environment(\.theme) private var theme
    @Environment(\.surface) private var surface
    private var font: Font { theme.isPixel ? .pixel(narrow ? 8 : 10) : (narrow ? Font.caption : Font.subheadline).weight(.semibold) }

    var body: some View {
        Group {
            if let running {
                let stack = narrow ? AnyLayout(VStackLayout(spacing: 1)) : AnyLayout(HStackLayout(spacing: 6))
                stack {
                    Text(choice.title)
                    if choice != .point {      // a point count shows its time left on the spectrogram
                        Text(timerInterval: running...Date.distantFuture, countsDown: false).monospacedDigit()
                            .accessibilityLabel("Listening time")
                    }
                }
                .font(font).foregroundStyle(surface.ink.opacity(0.75)).lineLimit(1)
                .padding(.horizontal, narrow ? 6 : 14).padding(.vertical, narrow ? 2 : 6)
                .accessibilityElement(children: .combine)
            } else {
                Menu {
                    Picker("Mode", selection: $choice) {
                        ForEach(ModeChoice.allCases) { c in
                            Label { Text(c.title); Text(c.brief) } icon: { Image(systemName: c.symbol) }.tag(c)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(choice.title).lineLimit(1).fixedSize()
                        Image(systemName: "chevron.up.chevron.down").imageScale(.small).fontWeight(.bold).opacity(0.7)
                    }
                    .font(font).foregroundStyle(surface.ink)
                    .padding(.horizontal, narrow ? 8 : 14).padding(.vertical, 6)
                    .background(surface.ink.opacity(0.12), in: theme.isPixel ? AnyShape(Rectangle()) : AnyShape(Capsule()))
                    .contentShape(Capsule())
                }
                .menuOrder(.fixed)
                .accessibilityLabel("Mode")
                .accessibilityValue(choice.title)
                .accessibilityHint("Picks what the big button does")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)       // a fixed bar, like the system tab bar
        .frame(minHeight: narrow ? 34 : 32)               // idle and listening take the same room
    }
}

struct ListenButton: View {
    @Environment(Listener.self) private var listener
    @Environment(\.theme) private var theme
    @Environment(\.surface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var choice: ModeChoice = .live
    /// Recordings: the button opens the file analysis instead of the microphone.
    var files: () -> Void = {}
    var body: some View {
        let listening = listener.state == .listening
        let style = ListenStyle(theme: theme, listening: listening)
        // -70 dB (a still room) to -25 dB (a bird close by)
        let level: CGFloat = listening ? CGFloat(min(max((listener.levelDB + 70) / 45, 0), 1)) : 0
        let analyzing = FileAnalysis.shared.running      // the models are busy: the button leads to what's keeping them
        Button { if (choice == .files || analyzing) && !listening { files() } else { Task { await listener.toggle() } } } label: {
            ZStack {
                if theme.isPixel {   // a chunky square key with a hard drop shadow
                    Rectangle().fill(style.shadow).frame(width: 62, height: 62).offset(x: 5, y: 5)
                    Rectangle().fill(style.fill).frame(width: 62, height: 62)
                        .overlay { Rectangle().stroke(style.ring, lineWidth: 3) }
                } else {
                    Circle().stroke(theme == .classic ? surface.ink.opacity(0.16) : style.ring, lineWidth: 4).frame(width: 78, height: 78)
                    // The ring listens: it lights up and swells a touch with the microphone level.
                    Circle().stroke(surface.accent, lineWidth: 4).frame(width: 78, height: 78)
                        .opacity(level).scaleEffect(reduceMotion ? 1 : 1 + 0.045 * level)
                        .animation(.linear(duration: 0.12), value: level)
                    Circle().fill(style.fill).frame(width: 66, height: 66)
                        .shadow(color: style.glow ?? .clear, radius: style.glow == nil ? 0 : 14)
                }
                if listener.state == .loading {
                    ProgressView().tint(style.glyph)
                } else {
                    Image(systemName: listening ? "stop.fill" : analyzing ? ModeChoice.files.symbol : choice.symbol)
                        .font(.system(size: listening ? 24 : 27, weight: .semibold)).foregroundStyle(style.glyph)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 80, height: 80)
            .animation(.snappy, value: listening)
        }
        .buttonStyle(.plain)
        .disabled(listener.state == .loading)
        .accessibilityLabel(listening ? "Stop listening" : analyzing ? "Analyzing recordings. Show progress" : choice == .files ? "Analyze recordings" : "Start listening, \(choice.title)")
        .sensoryFeedback(.impact(weight: .medium), trigger: listening)
    }
}

private struct BarButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.surface) private var surface
    @Environment(\.theme) private var theme
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.title3).frame(width: 44, height: 42)
                    .background { (theme.isPixel ? AnyShape(Rectangle()) : AnyShape(Circle())).fill(surface.ink.opacity(0.1)).frame(width: 42, height: 42) }
                Text(title).font(.caption2.weight(.medium)).lineLimit(1).opacity(0.75)
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)       // like the system tab bar: labels stop growing
            .frame(width: 76, height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(surface.ink)
    }
}

// MARK: Rows

/// The columns every row on the Listen list shares, so discs of every size center on one line.
private enum RowMetrics {
    static func column(_ compact: Bool) -> CGFloat { compact ? 38 : 48 }
    static func spacing(_ compact: Bool) -> CGFloat { compact ? 10 : 14 }
}

/// The small line under a name on the list: numbers in the surface's ink, a little quieter than the name.
private struct RowDetail<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.surface) private var surface
    var body: some View {
        HStack(spacing: 5) { content }
            .font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(surface.ink.opacity(0.62)).lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// Something calling right now: the biggest name on the list, with a ring around its disc for how sure Hark is.
struct NowRow: View {
    let label: HarkCore.Label
    let confidence: Float
    /// Both models backed it (Both mode).
    var agreed = false
    /// Its Journal entry, once it has one.
    var detection: Detection?
    @Environment(\.compactRows) private var compact
    @Environment(\.theme) private var theme
    @Environment(\.surface) private var surface
    @ScaledMetric(relativeTo: .title3) private var scale = 1.0
    var body: some View {
        let name = NameBook.shared.primary(label.common, label.scientific, species: label.group.isSpecies)
        HStack(spacing: RowMetrics.spacing(compact)) {
            StageDisc(group: label.group, size: compact ? 30 : 36, ring: Fusion.display(confidence))
                .frame(width: RowMetrics.column(compact), height: RowMetrics.column(compact))
            VStack(alignment: .leading, spacing: 2) {
                Text(name.text).font(theme.captionFont((compact ? 18 : 22) * scale)).italic(name.italic)
                    .lineLimit(2).minimumScaleFactor(0.8)
                RowDetail {
                    if agreed {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(surface.accent).accessibilityLabel("Perch and BirdNET+ agree")
                    }
                    Text("\(confidence.shownPercent)%")
                    if detection?.confirmed == true {
                        Image(systemName: "eye.fill").foregroundStyle(surface.accent).accessibilityLabel("You saw it")
                    }
                    if detection?.isFirst == true { NewBadge() }
                    if !compact, let other = NameBook.shared.secondary(label.common, label.scientific, species: label.group.isSpecies) {
                        Text(other.text).font(theme.captionFont(13 * scale, strong: false)).italic(other.italic)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 50)
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
    @Environment(\.compactRows) private var compact
    @Environment(\.theme) private var theme
    @Environment(\.surface) private var surface
    @ScaledMetric(relativeTo: .title3) private var scale = 1.0
    var body: some View {
        let below = compact || typeSize.isAccessibilitySize      // no room beside the name: the buttons go under it
        HStack(spacing: RowMetrics.spacing(compact)) {
            StageDisc(group: label.group, size: compact ? 26 : 30, mark: maybe.unusual ? "exclamationmark.circle.fill" : "questionmark.circle.fill")
                .frame(width: RowMetrics.column(compact))
                .opacity(maybe.unusual ? 1 : 0.75)
            VStack(alignment: .leading, spacing: 2) {
                Text(maybe.unusual ? label.displayName : "\(label.displayName)?")
                    .font(theme.captionFont((compact ? 16 : 18) * scale, strong: maybe.unusual))
                    .foregroundStyle(surface.ink.opacity(maybe.unusual ? 1 : 0.72)).lineLimit(2).minimumScaleFactor(0.8)
                RowDetail {
                    if maybe.unusual {
                        Text("\(listener.unusualReason(maybe.index)) · \(maybe.best.shownPercent)%").foregroundStyle(.orange)
                    } else {
                        Text("maybe · \(maybe.best.shownPercent)%")
                    }
                }
                if below { HStack(spacing: 7) { buttons }.padding(.top, 4) }
            }
            Spacer(minLength: 0)
            if !below { buttons }
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder private var buttons: some View {
        Button("Log it") { listener.logMaybe(maybe, confirmed: false) }
            .buttonStyle(SurfaceChip())
        Button { listener.logMaybe(maybe, confirmed: true) } label: { Image(systemName: "eye") }
            .buttonStyle(SurfaceChip(tint: surface.accent)).accessibilityLabel("I saw it")
    }
}

/// Heard earlier this session (or logged by hand): quieter than what's calling now, with "I saw it" beside it.
private struct HeardRow: View {
    let group: TaxonGroup
    let common: String
    let scientific: String
    let detail: String
    let detection: Detection?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.compactRows) private var compact
    @Environment(\.theme) private var theme
    @Environment(\.surface) private var surface
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    var body: some View {
        let name = NameBook.shared.primary(common, scientific, species: group.isSpecies)
        HStack(spacing: RowMetrics.spacing(compact)) {
            StageDisc(group: group, size: compact ? 24 : 28).frame(width: RowMetrics.column(compact))
            VStack(alignment: .leading, spacing: 2) {
                Text(name.text).font(theme.captionFont((compact ? 15 : 17) * scale, strong: false)).italic(name.italic)
                    .lineLimit(2).minimumScaleFactor(0.8)
                if let other = NameBook.shared.rowSecondary(common, scientific, species: group.isSpecies) {
                    Text(other.text).font(theme.captionFont(12 * scale, strong: false)).italic(other.italic).foregroundStyle(surface.ink.opacity(0.62)).lineLimit(1)
                }
                RowDetail {      // the badge sits here so the name keeps the whole line
                    if detection?.isFirst == true { NewBadge() }
                    Text(detail)
                }
                if typeSize.isAccessibilitySize, let d = detection { ConfirmButton(detection: d).padding(.top, 4) }
            }
            .foregroundStyle(surface.ink.opacity(0.9))
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize, let d = detection { ConfirmButton(detection: d) }
        }
        .frame(minHeight: 42)
    }
}

struct ManualRow: View {
    let detection: Detection
    var body: some View {
        HeardRow(group: detection.taxon, common: detection.common, scientific: detection.scientific,
                 detail: "\(detection.firstHeard.formatted(date: .omitted, time: .shortened)) · by hand · \(detection.confidence.shownPercent)%",
                 detection: detection)
    }
}

struct SessionRow: View {
    let label: HarkCore.Label
    let occurrence: DetectionTracker.Occurrence
    let detection: Detection?
    private var subtitle: String {
        var s = "\(occurrence.firstHeard.formatted(date: .omitted, time: .shortened)) · \(occurrence.bestConfidence.shownPercent)%"
        let mins = Int(occurrence.lastHeard.timeIntervalSince(occurrence.firstHeard) / 60)
        if mins >= 1 { s += " · \(mins) min" }
        return s
    }
    var body: some View {
        HeardRow(group: label.group, common: label.common, scientific: label.scientific, detail: subtitle, detection: detection)
    }
}

extension EnvironmentValues {
    /// Narrow landscape column: rows drop secondary detail and buttons go icon-only.
    @Entry var compactRows = false
    /// Show a detection's page from wherever this is: pushed in the Journal, a sheet over the Listen screen.
    @Entry var openDetection: ((Detection) -> Void)?
}

/// A detection's page over the Listen screen, with the same ways onward as in the Journal (its species, its session).
struct DetectionSheet: View {
    let detection: Detection
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) {
            DetectionDetail(detection: detection)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .navigationDestination(for: Detection.self) { DetectionDetail(detection: $0) }
                .navigationDestination(for: SessionSummary.self) { SessionPage(session: $0) }
                .navigationDestination(for: SpeciesKey.self) { SpeciesPage(scientific: $0.scientific) }
        }
        .environment(\.openDetection) { path.append($0) }
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 12) }
    }
}

struct ConfirmButton: View {
    @Bindable var detection: Detection
    @Environment(\.compactRows) private var compact
    @Environment(\.surface) private var surface
    var body: some View {
        Button { detection.confirmed.toggle() } label: {
            Label(detection.confirmed ? "Saw it" : "I saw it", systemImage: detection.confirmed ? "checkmark" : "eye")
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        }
        .buttonStyle(SurfaceChip(tint: detection.confirmed ? surface.good : surface.ink.opacity(0.85), on: detection.confirmed))
        .sensoryFeedback(.selection, trigger: detection.confirmed)
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
    @Environment(\.openDetection) private var open
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { if let detection { open?(detection) } }
            .accessibilityAction(named: "Open") { if let detection { open?(detection) } }
            .sheet(item: $sharing) { d in ShareCardSheet(detection: d).themeRoot() }
            .swipeActions(edge: .trailing) {
                // Full swipe = Not it (this time only); muting for good is the second, deliberate button.
                Button(role: .destructive) { withAnimation { listener.notIt(index) } } label: { Label("Not it", systemImage: "xmark") }
                Button { listener.mute(index) } label: { Label("Never show", systemImage: "speaker.slash") }.tint(.gray)
            }
            .contextMenu { SpeciesMenu(index: index, detection: detection, maybe: maybe) { sharing = $0 } }
    }
}

/// Everything you can do with a species, for a long-press on a row or a caption.
struct SpeciesMenu: View {
    @Environment(Listener.self) private var listener
    @Environment(\.openDetection) private var open
    let index: Int
    var detection: Detection?
    var maybe: Maybe?
    var share: (Detection) -> Void
    var body: some View {
        if let m = maybe {
            Button { listener.logMaybe(m, confirmed: false) } label: { Label("Log it", systemImage: "plus") }
            Button { listener.logMaybe(m, confirmed: true) } label: { Label("I saw it", systemImage: "eye") }
        }
        if let d = detection {
            Button { open?(d) } label: { Label("Open", systemImage: "doc.text.magnifyingglass") }
            Button { d.confirmed.toggle() } label: {
                Label(d.confirmed ? "I didn't see it" : "I saw it", systemImage: d.confirmed ? "eye.slash" : "eye")
            }
            Button { share(d) } label: { Label("Share…", systemImage: "square.and.arrow.up") }
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

/// Lets a view switch label styles at run time.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
