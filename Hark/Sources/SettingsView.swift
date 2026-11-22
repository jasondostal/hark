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
          ScrollViewReader { proxy in
            Form {
                detection
                listenFor
                location.id("location")
                ebirdSection
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
            .onAppear {
                inputs = AudioCapture.inputs(); listener.updateContext()
                if ProcessInfo.processInfo.arguments.contains("-settingslocation") {   // screenshot aid
                    Task { try? await Task.sleep(for: .seconds(1)); proxy.scrollTo("location", anchor: .top) }
                }
            }
          }
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
                        TaxonIcon(group: g.taxon, size: 32, faint: !s.enabled)
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

    // MARK: Location & season

    private var location: some View {
        @Bindable var listener = listener
        return Section {
            Picker("Unexpected species", selection: $listener.policy.rangeMode) {
                Text("Off").tag(RangeMode.off); Text("Flag").tag(RangeMode.flag); Text("Hide").tag(RangeMode.hide)
            }
            .pickerStyle(.segmented)
            if listener.policy.rangeMode != .off {
                if let c = listener.context {
                    if listener.geoAvailable { LabeledContent("Expected this week", value: "\(c.expectedThisWeek.formatted()) species") }
                    if let r = listener.localRange { LabeledContent("Ever recorded nearby", value: "\(r.speciesHere.formatted()) species") }
                    LabeledContent("Your patch", value: listener.patch.isEmpty ? "None yet" : "\(listener.patch.count) species")
                } else {
                    LabeledContent("Status", value: listener.rangeAvailable ? "Waiting for location" : "No range data in this build")
                }
            }
        } header: { Text("Location & season") } footer: {
            Text("Flag shows IDs that don't fit the place or time of year as \"unusual\" and only logs them if you tap; Hide drops them. Hark checks the BirdNET geomodel (where each species is, week by week) and GBIF records within about 150 km. Species you've confirmed near here, your patch, are never flagged.")
        }
    }

    private var ebirdSection: some View {
        let eb = listener.ebird
        return Section {
            SecureField("Paste your eBird API key", text: Binding(get: { eb.key }, set: { eb.key = $0; listener.rebuildContext(); listener.updateContext() }))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if eb.hasKey {
                if let c = eb.cache {
                    LabeledContent("Reported nearby", value: "\(Set(c.reports.map(\.speciesCode)).count) species")
                    LabeledContent("Updated", value: c.fetched.formatted(.relative(presentation: .named)))
                }
                if let e = eb.lastError { Text(e).font(.callout).foregroundStyle(.red) }
                Button(eb.fetching ? "Checking eBird…" : "Refresh now") {
                    Task { await listener.refreshEBird() }
                }
                .disabled(eb.fetching)
            } else {
                Link(destination: URL(string: "https://ebird.org/api/keygen")!) {
                    Label("Get a free key from eBird", systemImage: "key")
                }
            }
        } header: { Text("eBird (optional)") } footer: {
            Text("With your own eBird key, species birders reported within 25 km in the last 30 days are never flagged, so this week's migrants count. Hark sends eBird your location rounded to about 1 km, only while a key is set.")
        }
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
            Picker("Time shown", selection: $listener.spectrogramSeconds) {
                Text("5 s").tag(5); Text("10 s").tag(10); Text("15 s").tag(15); Text("30 s").tag(30)
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                HStack { Text("Contrast"); Spacer(); Text(listener.contrast < 0.34 ? "Soft" : listener.contrast > 0.67 ? "Punchy" : "Medium").foregroundStyle(.secondary) }
                Slider(value: $listener.contrast, in: 0...1)
            }
            Toggle("Frequency labels", isOn: $listener.frequencyLabels)
        } header: { Text("Spectrogram") } footer: {
            Text("Owling is all red, to keep your night vision on an owl prowl. Punchy contrast makes faint calls stand out but also shows more background. Colors and contrast don't change what Hark identifies.")
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
            Picker("Identify", selection: $listener.idMode) {
                Text("Auto").tag(Listener.IDMode.auto); Text("Manual").tag(Listener.IDMode.manual)
            }
            .pickerStyle(.segmented)
            Toggle("Keep screen on", isOn: $listener.keepScreenOn)
            Picker("Stop listening after", selection: $listener.stopAfterMinutes) {
                Text("15 min").tag(15); Text("30 min").tag(30); Text("1 hour").tag(60)
                Text("2 hours").tag(120); Text("4 hours").tag(240); Text("Never").tag(0)
            }
        } header: { Text("Listening") } footer: {
            Text("Auto identifies everything it hears and keeps logging with the screen locked (shown on the Lock Screen and Dynamic Island; a new species buzzes the phone). Manual only identifies what you select on the spectrogram. Either way, touch the spectrogram to pick out a call from the last minute.")
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
            LabeledContent("Seasons", value: "BirdNET Geomodel")
            LabeledContent("Names", value: "OpenFauna")
            LabeledContent("Frog icon", value: "Font Awesome (CC BY 4.0)")
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
                            Label { Text(g.title) } icon: { TaxonIcon(group: g.taxon, size: 26) }
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
