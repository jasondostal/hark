import SwiftUI
import SwiftData
import HarkCore

/// Home: a big live spectrogram on top, what's being heard in the middle, and a camera-style bar at the bottom
/// (Log · Listen · Settings) where the thumb already is.
struct ListenView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.modelContext) private var ctx
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("-settings")   // screenshot aids
    @State private var showLog = ProcessInfo.processInfo.arguments.contains("-logtab")

    var body: some View {
        @Bindable var listener = listener
        VStack(spacing: 0) {
            spectrogramPanel
            List { content }
                .listStyle(.insetGrouped)
                .contentMargins(.top, 8, for: .scrollContent)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .overlay(alignment: .bottom) { celebration.padding(.bottom, 120) }
        .animation(.spring, value: listener.celebration?.id)
        .sheet(item: $listener.rewind) { RewindView(clip: $0) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLog) { LogView() }
        .onAppear {
            listener.modelContext = ctx
            WidgetBridge.refresh(ctx, listening: listener.state == .listening, now: true)
        }
    }

    // MARK: Spectrogram

    private var spectrogramPanel: some View {
        SpectrogramView(source: listener.live, running: listener.state == .listening,
                        palette: listener.palette, frequencyLabels: listener.frequencyLabels)
            .frame(height: 250)
            .contentShape(Rectangle())
            .onTapGesture { if listener.canRewind { listener.openRewind() } }
            .overlay(alignment: .bottom) {
                HStack(spacing: 12) {
                    Button { listener.openRewind() } label: {
                        Label("Rewind", systemImage: "gobackward")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(listener.palette == .paper ? .black : .white)
                    .disabled(!listener.canRewind)
                    Spacer()
                    if listener.state == .listening {
                        Image(systemName: "mic.fill").font(.caption).foregroundStyle(listener.palette.labelColor)
                        LevelBar(db: listener.levelDB).frame(width: 70)
                            .accessibilityLabel("Microphone level")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(LinearGradient(colors: [.clear, .black.opacity(listener.palette == .paper ? 0 : 0.45)],
                                           startPoint: .top, endPoint: .bottom))
            }
    }

    // MARK: Hearing now / this session

    @ViewBuilder private var content: some View {
        switch listener.state {
        case .loading:
            Section { HStack(spacing: 10) { ProgressView(); Text("Getting Perch ready… (the first launch takes a moment)").font(.callout) } }
        case .failed(let msg):
            Section { Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
        default: EmptyView()
        }
        let active = listener.state == .listening || !listener.session.isEmpty || !listener.manual.isEmpty
        if !active && listener.state == .ready {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hear something?").font(.title3.bold())
                    Tip(symbol: "ear", text: "Tap **Listen**. Birds, frogs, insects and mammals show up here as Hark hears them.")
                    Tip(symbol: "gobackward", text: "Missed it? **Rewind** the last minute and pick out the call.")
                    Tip(symbol: "button.horizontal.top.press", text: "Put **Start Listening** on your Action Button. See Settings.")
                }
                .padding(.vertical, 6)
            }
        }
        if active {
            Section("Hearing now") {
                if listener.hearingNow.isEmpty && listener.maybes.isEmpty {
                    Text(listener.state == .listening ? "Listening…" : "Stopped").foregroundStyle(.secondary)
                }
                ForEach(listener.hearingNow) { o in
                    if let l = listener.label(o.index) { NowRow(label: l, confidence: o.bestConfidence).muteSwipe(o.index) }
                }
                ForEach(listener.maybes) { m in
                    if let l = listener.label(m.index) { MaybeRow(label: l, maybe: m).muteSwipe(m.index) }
                }
            }
            if !listener.session.isEmpty || !listener.manual.isEmpty {
                Section("This session") {
                    ForEach(listener.manual) { d in ManualRow(detection: d) }
                    ForEach(listener.session) { o in
                        if let l = listener.label(o.index) {
                            SessionRow(label: l, occurrence: o, detection: listener.detection(for: o)).muteSwipe(o.index)
                        }
                    }
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center) {
            BarButton(title: "Log", symbol: "list.bullet.rectangle.portrait") { showLog = true }
            Spacer()
            ListenButton()
            Spacer()
            BarButton(title: "Settings", symbol: "slider.horizontal.3") { showSettings = true }
        }
        .padding(.horizontal, 30).padding(.top, 10).padding(.bottom, 2)
        .background(.bar)
    }

    @ViewBuilder private var celebration: some View {
        if let c = listener.celebration {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.yellow)
                VStack(alignment: .leading) {
                    Text("New for you!").font(.caption.weight(.bold)).foregroundStyle(.orange)
                    Text(c.name).font(.headline)
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
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 22)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// The shutter-style Listen / Stop button.
struct ListenButton: View {
    @Environment(Listener.self) private var listener
    var body: some View {
        let listening = listener.state == .listening
        Button { Task { await listener.toggle() } } label: {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(listening ? Color.red : Color.green).frame(width: 66, height: 66)
                if listener.state == .loading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: listening ? "stop.fill" : "ear")
                        .font(.system(size: listening ? 24 : 28, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(listener.state == .loading)
        .accessibilityLabel(listening ? "Stop listening" : "Start listening")
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
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(width: 66, height: 54)
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
    var body: some View {
        HStack(spacing: 12) {
            TaxonIcon(emoji: label.icon, group: label.group)
            VStack(alignment: .leading) {
                Text(label.common).font(.headline)
                if label.group.isSpecies { Text(label.scientific).font(.caption).italic().foregroundStyle(.secondary) }
            }
            Spacer()
            ConfidenceBar(value: confidence)
        }
    }
}

/// Not logged automatically; one tap logs it or logs it as seen.
/// Maybe = plausible but under the threshold (faint, "?"). Unusual = confident but never recorded near you (orange).
struct MaybeRow: View {
    @Environment(Listener.self) private var listener
    let label: HarkCore.Label
    let maybe: Maybe
    var body: some View {
        HStack(spacing: 12) {
            TaxonIcon(emoji: label.icon, group: label.group, faint: !maybe.unusual)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: maybe.unusual ? "exclamationmark.circle.fill" : "questionmark.circle.fill")
                        .font(.caption).foregroundStyle(.white, maybe.unusual ? Color.orange : Color.gray)
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading) {
                Text(maybe.unusual ? label.common : "\(label.common)?")
                    .foregroundStyle(maybe.unusual ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                Text("\(maybe.unusual ? "unusual here" : "maybe") · \(Int(maybe.best * 100))%")
                    .font(.caption).foregroundStyle(maybe.unusual ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            }
            Spacer()
            Button { listener.logMaybe(maybe, confirmed: false) } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered).accessibilityLabel("Log it")
            Button { listener.logMaybe(maybe, confirmed: true) } label: { Image(systemName: "eye") }
                .buttonStyle(.bordered).tint(.green).accessibilityLabel("I saw it")
        }
    }
}

struct ManualRow: View {
    let detection: Detection
    var body: some View {
        HStack(spacing: 12) {
            TaxonIcon(emoji: detection.icon, group: detection.taxon)
            VStack(alignment: .leading) {
                HStack(spacing: 6) { Text(detection.common); if detection.isFirst { NewBadge() } }
                Text("\(detection.firstHeard.formatted(date: .omitted, time: .shortened)) · logged by hand · \(Int(detection.confidence * 100))%")
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
    var body: some View {
        HStack(spacing: 12) {
            TaxonIcon(emoji: label.icon, group: label.group)
            VStack(alignment: .leading) {
                HStack(spacing: 6) { Text(label.common); if detection?.isFirst == true { NewBadge() } }
                Text("\(occurrence.firstHeard.formatted(date: .omitted, time: .shortened)) · best \(Int(occurrence.bestConfidence * 100))% · \(occurrence.windows)×")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let d = detection { ConfirmButton(detection: d) }
        }
    }
}

struct ConfirmButton: View {
    @Bindable var detection: Detection
    var body: some View {
        Button { detection.confirmed.toggle() } label: {
            Label(detection.confirmed ? "Saw it" : "I saw it",
                  systemImage: detection.confirmed ? "checkmark.seal.fill" : "eye")
                .font(.caption).labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .tint(detection.confirmed ? .green : .secondary)
    }
}

struct ConfidenceBar: View {
    let value: Float
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor).frame(width: g.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(width: 56, height: 6)
            Text("\(Int(value * 100))%").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
        }
    }
}

struct LevelBar: View {
    let db: Float
    var body: some View {
        let v = CGFloat(min(max((db + 80) / 70, 0), 1))
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.green.gradient).frame(width: g.size.width * v)
            }
        }
        .frame(height: 5)
        .animation(.linear(duration: 0.1), value: v)
    }
}

extension View {
    /// Swipe left: "Never show" this species.
    func muteSwipe(_ index: Int) -> some View { modifier(MuteSwipe(index: index)) }
}

private struct MuteSwipe: ViewModifier {
    @Environment(Listener.self) private var listener
    let index: Int
    func body(content: Content) -> some View {
        content.swipeActions(edge: .trailing) {
            Button(role: .destructive) { listener.mute(index) } label: { Label("Never show", systemImage: "speaker.slash") }
        }
    }
}
