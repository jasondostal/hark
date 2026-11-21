import SwiftUI
import SwiftData
import HarkCore

struct ListenView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.modelContext) private var ctx
    @State private var showSettings = false

    var body: some View {
        @Bindable var listener = listener
        NavigationStack {
            List {
                Section {
                    SpectrogramView(source: listener.live, running: listener.state == .listening)
                        .frame(height: 130)
                        .overlay(alignment: .topTrailing) {
                            if listener.canRewind {
                                Label("Rewind", systemImage: "gobackward")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.ultraThinMaterial.opacity(0.6), in: Capsule()).padding(8)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { listener.openRewind() }
                        .listRowInsets(EdgeInsets())
                    controls
                }
                if listener.state == .listening || !listener.session.isEmpty || !listener.manual.isEmpty {
                    Section("Hearing now") {
                        if listener.hearingNow.isEmpty && listener.maybes.isEmpty {
                            Text(listener.state == .listening ? "Listening…" : "Stopped")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(listener.hearingNow) { o in
                            if let l = listener.label(o.index) {
                                NowRow(label: l, confidence: o.bestConfidence).muteSwipe(o.index)
                            }
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
            .overlay(alignment: .bottom) {
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
                    .shadow(radius: 8).padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring, value: listener.celebration?.id)
            .navigationTitle("Hark")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .sheet(item: $listener.rewind) { RewindView(clip: $0) }
            .sheet(isPresented: $showSettings) { SettingsView().presentationDetents([.medium, .large]) }
            .onAppear {
                listener.modelContext = ctx
                if ProcessInfo.processInfo.arguments.contains("-settings") { showSettings = true }   // screenshot aid
            }
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            switch listener.state {
            case .loading:
                HStack { ProgressView(); Text("Loading Perch… (first launch compiles the model)") }
                    .font(.footnote).foregroundStyle(.secondary)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote)
            default: EmptyView()
            }
            Button {
                Task { await listener.toggle() }
            } label: {
                Label(listener.state == .listening ? "Stop" : "Listen",
                      systemImage: listener.state == .listening ? "stop.fill" : "ear")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(listener.state == .listening ? .red : .accentColor)
            .disabled(listener.state == .loading)

            if listener.state == .listening {
                HStack {
                    LevelBar(db: listener.levelDB)
                    Text(String(format: "%.0f ms", listener.lastInferenceMs))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct NowRow: View {
    let label: HarkCore.Label
    let confidence: Float
    var body: some View {
        HStack {
            Image(systemName: label.group.symbol).frame(width: 28).foregroundStyle(label.group.isSpecies ? Color.accentColor : .secondary)
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
/// Maybe = plausible but under the threshold (faint, "?"). Unusual = confident but never recorded near you (orange flag).
struct MaybeRow: View {
    @Environment(Listener.self) private var listener
    let label: HarkCore.Label
    let maybe: Maybe
    var body: some View {
        HStack {
            Image(systemName: maybe.unusual ? "exclamationmark.triangle" : "questionmark.circle").frame(width: 28)
                .foregroundStyle(maybe.unusual ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading) {
                Text(maybe.unusual ? label.common : "\(label.common)?")
                    .foregroundStyle(maybe.unusual ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                Text("\(maybe.unusual ? "unusual here" : "maybe") · \(Int(maybe.best * 100))%")
                    .font(.caption).foregroundStyle(maybe.unusual ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            }
            Spacer()
            Button("Log") { listener.logMaybe(maybe, confirmed: false) }
                .buttonStyle(.bordered).font(.caption)
            Button { listener.logMaybe(maybe, confirmed: true) } label: { Label("I saw it", systemImage: "eye") }
                .buttonStyle(.bordered).tint(.green).font(.caption)
        }
    }
}

struct ManualRow: View {
    let detection: Detection
    var body: some View {
        HStack {
            Image(systemName: "hand.tap").frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(detection.common)
                Text("\(detection.firstHeard.formatted(date: .omitted, time: .shortened)) · logged from maybe · \(Int(detection.confidence * 100))%")
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
        HStack {
            Image(systemName: label.group.symbol).frame(width: 28).foregroundStyle(.secondary)
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
            .frame(width: 60, height: 6)
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
                Capsule().fill(.quaternary)
                Capsule().fill(.green.gradient).frame(width: g.size.width * v)
            }
        }
        .frame(height: 4)
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

struct SettingsView: View {
    @Environment(Listener.self) private var listener
    var body: some View {
        @Bindable var listener = listener
        NavigationStack {
            Form {
                Section {
                    ForEach(ListenGroup.allCases, id: \.self) { g in GroupRow(group: g) }
                } header: { Text("Listen for") } footer: {
                    Text("Each group has its own confidence threshold (a softmax over all 14,795 Perch classes). Lower shows more, with more wrong guesses. Species between half the threshold and the threshold show as faint \"maybe\" rows you can log by hand. Non-animal sounds show but are never logged.")
                }
                Section {
                    Picker("Out-of-range species", selection: $listener.policy.rangeMode) {
                        Text("Off").tag(RangeMode.off)
                        Text("Flag").tag(RangeMode.flag)
                        Text("Hide").tag(RangeMode.hide)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Status", value: rangeStatus)
                } header: { Text("Location filter") } footer: {
                    Text("Compares each ID with species recorded within roughly 150 km of you. Flag shows out-of-range IDs as \"unusual here\" and doesn't log them unless you tap Log; Hide drops them. Species with no records anywhere are never filtered. Range data: GBIF.org occurrence records.")
                }
                Section {
                    Toggle("Keep screen on", isOn: $listener.keepScreenOn)
                    Picker("Stop listening after", selection: $listener.stopAfterMinutes) {
                        Text("15 min").tag(15); Text("30 min").tag(30); Text("1 hour").tag(60)
                        Text("2 hours").tag(120); Text("4 hours").tag(240); Text("Never").tag(0)
                    }
                } header: { Text("Listening") } footer: {
                    Text("Hark keeps listening and logging with the screen locked, shown on the Lock Screen and Dynamic Island. A new species buzzes the phone.")
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Action Button", systemImage: "button.horizontal.top.press").font(.headline)
                        Text("Settings › Action Button › Controls (or Shortcut) › Hark › Start Listening")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Control Center or Lock Screen", systemImage: "switch.2").font(.headline)
                        Text("Edit Control Center or your Lock Screen, add a control, search for Hark.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Or ask Siri: \"Listen with Hark.\"").font(.callout).foregroundStyle(.secondary)
                } header: { Text("Start listening in one press") }
                if !listener.mutedNames.isEmpty {
                    Section {
                        ForEach(listener.mutedNames, id: \.self) { name in
                            HStack {
                                Text(listener.commonName(name))
                                Spacer()
                                Button("Unmute") { listener.unmute(name) }.font(.caption).buttonStyle(.bordered)
                            }
                        }
                    } header: { Text("Never show") } footer: {
                        Text("Swipe left on any ID to add it here.")
                    }
                }
                Section("Model") {
                    LabeledContent("Perch 2.0", value: "14,795 classes")
                    LabeledContent("Last window", value: String(format: "%.1f ms", listener.lastInferenceMs))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var rangeStatus: String {
        if !listener.rangeAvailable { return "No range data in this build" }
        if listener.policy.rangeMode == .off { return "Off" }
        guard let r = listener.localRange else { return "Waiting for location" }
        return "\(r.speciesHere.formatted()) species recorded here"
    }
}

struct GroupRow: View {
    @Environment(Listener.self) private var listener
    let group: ListenGroup
    var body: some View {
        let s = listener.policy.setting(group)
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { s.enabled }, set: { v in listener.policy.set(group, GroupSetting(enabled: v, threshold: s.threshold)) })) {
                Label(group.title, systemImage: group.symbol)
            }
            if s.enabled {
                HStack {
                    Slider(value: Binding(get: { s.threshold }, set: { v in listener.policy.set(group, GroupSetting(enabled: true, threshold: v)) }),
                           in: 0.1...0.9, step: 0.05)
                    Text("\(Int(s.threshold * 100))%").font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
                }
            }
        }
    }
}
