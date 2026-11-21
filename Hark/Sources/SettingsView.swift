import SwiftUI
import AVFoundation
import HarkCore

struct SettingsView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    @State private var inputs: [AVAudioSessionPortDescription] = []

    var body: some View {
        @Bindable var listener = listener
        NavigationStack {
            Form {
                detection
                listenFor
                location
                spectrogram
                audio
                listening
                oneTouch
                if !listener.mutedNames.isEmpty { muted }
                about
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { inputs = AudioCapture.inputs() }
        }
    }

    // MARK: Detection

    private var presetBinding: Binding<Preset?> {
        Binding(get: { listener.policy.preset }, set: { if let p = $0 { listener.policy.apply(p) } })
    }

    private var detection: some View {
        Section {
            Picker("How picky", selection: presetBinding) {
                ForEach(Preset.allCases, id: \.self) { Text($0.title).tag(Preset?.some($0)) }
                if listener.policy.preset == nil { Text("Custom").tag(Preset?.none) }
            }
            .pickerStyle(.segmented)
            Text(listener.policy.preset?.blurb ?? "You've fine-tuned the thresholds below. Pick a preset to reset them.")
                .font(.callout).foregroundStyle(.secondary)
        } header: { Text("Detection") } footer: {
            Text("Why the numbers look low: Perch splits 100% across 14,795 sounds, so its confidence runs far below BirdNET's. On 48 backyard recordings BirdNET-Go logged at 80–100%, Perch scored a median of 70%. A 30% bar (Balanced) would have logged 75% of them; an 85% bar only 25%.")
        }
    }

    private var listenFor: some View {
        Section {
            ForEach(ListenGroup.allCases, id: \.self) { g in
                let s = listener.policy.setting(g)
                Toggle(isOn: Binding(get: { s.enabled }, set: { v in listener.policy.set(g, GroupSetting(enabled: v, threshold: s.threshold)) })) {
                    HStack(spacing: 12) {
                        TaxonIcon(emoji: g.emoji, group: g.taxon, size: 32, faint: !s.enabled)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title)
                            Text(s.enabled ? caption(g, s) : "Off").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            NavigationLink("Fine-tune thresholds") { ThresholdsView() }
        } header: { Text("Listen for") }
    }

    private func caption(_ g: ListenGroup, _ s: GroupSetting) -> String {
        g == .sound ? "Shows at \(Int(s.threshold * 100))% · never logged"
                    : "Logs at \(Int(s.threshold * 100))% · maybes from \(Int(listener.policy.maybeFloor(g) * 100))%"
    }

    // MARK: Location

    private var location: some View {
        @Bindable var listener = listener
        return Section {
            Picker("Out-of-range species", selection: $listener.policy.rangeMode) {
                Text("Off").tag(RangeMode.off); Text("Flag").tag(RangeMode.flag); Text("Hide").tag(RangeMode.hide)
            }
            .pickerStyle(.segmented)
            LabeledContent("Status", value: rangeStatus)
        } header: { Text("Location filter") } footer: {
            Text("Compares each ID with species recorded within about 150 km of you. Flag shows out-of-range IDs as \"unusual here\" and only logs them if you tap; Hide drops them. Species with no records anywhere are never filtered.")
        }
    }

    private var rangeStatus: String {
        if !listener.rangeAvailable { return "No range data in this build" }
        if listener.policy.rangeMode == .off { return "Off" }
        guard let r = listener.localRange else { return "Waiting for location" }
        return "\(r.speciesHere.formatted()) species recorded here"
    }

    // MARK: Spectrogram

    private var spectrogram: some View {
        @Bindable var listener = listener
        return Section {
            Picker("Colors", selection: $listener.palette) {
                ForEach(SpectrogramPalette.allCases) { p in
                    HStack {
                        RoundedRectangle(cornerRadius: 3).fill(p.gradient).frame(width: 64, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
                        Text(p.title)
                    }
                    .tag(p)
                }
            }
            .pickerStyle(.navigationLink)
            VStack(alignment: .leading) {
                HStack { Text("Contrast"); Spacer(); Text(listener.contrast < 0.34 ? "Soft" : listener.contrast > 0.67 ? "Punchy" : "Medium").foregroundStyle(.secondary) }
                Slider(value: $listener.contrast, in: 0...1)
            }
            Toggle("Frequency labels", isOn: $listener.frequencyLabels)
        } header: { Text("Spectrogram") } footer: {
            Text("Punchy makes faint calls stand out but also shows more background. Colors and contrast don't change what Hark identifies.")
        }
    }

    // MARK: Audio

    private var audio: some View {
        @Bindable var listener = listener
        return Section {
            Picker("Microphone", selection: $listener.inputUID) {
                Text("Automatic").tag(String?.none)
                ForEach(inputs, id: \.uid) { p in Text(p.portName).tag(String?.some(p.uid)) }
            }
            Picker("Rumble filter", selection: $listener.rumbleFilter) {
                Text("Off").tag(0.0); Text("Light (80 Hz)").tag(80.0); Text("Strong (200 Hz)").tag(200.0)
            }
        } header: { Text("Audio") } footer: {
            Text("Plug in a USB-C or wired mic and pick it here (applies the next time you start listening). The rumble filter cuts wind, handling and road noise before Hark hears it; Strong can soften the lowest owl hoots and grouse drumming.")
        }
    }

    // MARK: Listening

    private var listening: some View {
        @Bindable var listener = listener
        return Section {
            Toggle("Keep screen on", isOn: $listener.keepScreenOn)
            Picker("Stop listening after", selection: $listener.stopAfterMinutes) {
                Text("15 min").tag(15); Text("30 min").tag(30); Text("1 hour").tag(60)
                Text("2 hours").tag(120); Text("4 hours").tag(240); Text("Never").tag(0)
            }
        } header: { Text("Listening") } footer: {
            Text("Hark keeps listening and logging with the screen locked, shown on the Lock Screen and Dynamic Island. A new species buzzes the phone.")
        }
    }

    private var oneTouch: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Action Button", systemImage: "button.horizontal.top.press").font(.headline)
                Text("Settings › Action Button › Controls › Hark › Start Listening").font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Control Center, Lock Screen, widgets", systemImage: "switch.2").font(.headline)
                Text("Add a control or widget and search for Hark.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Or ask Siri: \"Listen with Hark.\"").font(.callout).foregroundStyle(.secondary)
        } header: { Text("Start listening in one press") }
    }

    private var muted: some View {
        Section {
            ForEach(listener.mutedNames, id: \.self) { name in
                HStack {
                    Text(listener.commonName(name))
                    Spacer()
                    Button("Unmute") { listener.unmute(name) }.font(.caption).buttonStyle(.bordered)
                }
            }
        } header: { Text("Never show") } footer: { Text("Swipe left on any ID to add it here.") }
    }

    private var about: some View {
        Section {
            LabeledContent("Model", value: "Google Perch 2.0 · 14,795 sounds")
            LabeledContent("Speed", value: listener.lastInferenceMs > 0 ? String(format: "%.1f ms per 5 s of audio", listener.lastInferenceMs) : "—")
            LabeledContent("Range data", value: "GBIF.org")
            LabeledContent("Names", value: "OpenFauna")
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        } header: { Text("About") } footer: {
            Text("Everything runs on this iPhone. Audio never leaves it.")
        }
    }
}

/// Per-group sliders, for people who want them.
struct ThresholdsView: View {
    @Environment(Listener.self) private var listener
    var body: some View {
        Form {
            Section {
                ForEach(ListenGroup.allCases, id: \.self) { g in
                    let s = listener.policy.setting(g)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(g.emoji)  \(g.title)")
                            Spacer()
                            Text("\(Int(s.threshold * 100))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { s.threshold }, set: { v in listener.policy.set(g, GroupSetting(enabled: s.enabled, threshold: v)) }),
                               in: 0.1...0.9, step: 0.05)
                            .disabled(!s.enabled)
                    }
                    .opacity(s.enabled ? 1 : 0.4)
                }
            } footer: {
                Text("A sound at or above its group's threshold is logged. Between half the threshold and the threshold it shows as a maybe you can log by hand. Raise a group that gives you wrong IDs (insects are the usual suspect); lower one that misses quiet calls.")
            }
            Section {
                ForEach(Preset.allCases, id: \.self) { p in
                    Button("Reset to \(p.title)") { listener.policy.apply(p) }
                }
            }
        }
        .navigationTitle("Thresholds")
        .navigationBarTitleDisplayMode(.inline)
    }
}
