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
                        .listRowInsets(EdgeInsets())
                    controls
                }
                if listener.state == .listening || !listener.session.isEmpty {
                    Section("Hearing now") {
                        if listener.hearingNow.isEmpty && listener.maybes.isEmpty {
                            Text(listener.state == .listening ? "Listening…" : "Stopped")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(listener.hearingNow) { o in
                            if let l = listener.label(o.index) { NowRow(label: l, confidence: o.bestConfidence) }
                        }
                        ForEach(listener.maybes) { m in
                            if let l = listener.label(m.index) { MaybeRow(label: l, maybe: m) }
                        }
                    }
                    Section("This session") {
                        ForEach(listener.manual) { d in ManualRow(detection: d) }
                        ForEach(listener.session) { o in
                            if let l = listener.label(o.index) {
                                SessionRow(label: l, occurrence: o, detection: listener.detection(for: o))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hark")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView().presentationDetents([.medium]) }
            .onAppear { listener.modelContext = ctx }
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

/// Under the threshold but plausible. Faint, with a question mark; one tap logs it or logs it as seen.
struct MaybeRow: View {
    @Environment(Listener.self) private var listener
    let label: HarkCore.Label
    let maybe: Maybe
    var body: some View {
        HStack {
            Image(systemName: "questionmark.circle").frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text("\(label.common)?").foregroundStyle(.secondary)
                Text("maybe · \(Int(maybe.best * 100))%").font(.caption).foregroundStyle(.tertiary)
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
                Text(label.common)
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

struct SettingsView: View {
    @Environment(Listener.self) private var listener
    var body: some View {
        @Bindable var listener = listener
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Confidence threshold: \(Int(listener.threshold * 100))%")
                        Slider(value: $listener.threshold, in: 0.1...0.9, step: 0.05)
                    }
                } footer: {
                    Text("Confidence is a softmax over all 14,795 Perch classes. Lower shows more, with more wrong guesses. Species between half the threshold and the threshold show as faint \"maybe\" rows you can log by hand.")
                }
                Section {
                    Toggle("Show non-animal sounds", isOn: $listener.showSounds)
                } footer: {
                    Text("Cars, dogs, voices and other sound events. They show while listening but are never logged.")
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
}
