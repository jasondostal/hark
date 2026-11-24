import SwiftUI
import AVFoundation
import HarkCore

struct SettingsView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    @State private var inputs: [AVAudioSessionPortDescription] = []
    @State private var showLocation = ProcessInfo.processInfo.arguments.contains("-settingslocation")   // screenshot aid
    /// Screenshot aid: -settingspage Inference | Spectrogram | Audio
    @State private var showPage: String? = { let a = ProcessInfo.processInfo.arguments; return a.firstIndex(of: "-settingspage").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }()

    /// The top level holds what people change often (model, pickiness, what to listen for); everything else is one
    /// row each, showing its current value, that opens its own page.
    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    ThemePicker()
                    Picker("Names", selection: Binding(get: { NameBook.shared.style }, set: { NameBook.shared.style = $0 })) {
                        ForEach(NameBook.Style.allCases) { Text($0.title).tag($0) }
                    }
                } header: { Text("Look") } footer: {
                    Text("\(AppTheme.stored.title): \(AppTheme.stored.blurb) Each look brings its own spectrogram colors; change those under Spectrogram. Names: which name leads. Give a species your own name on its page in the Log.")
                }
                detection
                Section {
                    NavigationLink { page("Listen for") { listenFor } } label: {
                        row("Listen for", "pawprint", listenSummary)
                    }
                    NavigationLink { page("Location & season") { location; ebirdSection } } label: {
                        row("Location & season", "location", locationSummary)
                    }
                    NavigationLink { page("Inference") { inference; humanGuard } } label: {
                        row("Inference", "cpu", inferenceSummary)
                    }
                    NavigationLink { page("Spectrogram") { spectrogram; spectrogramTuning } } label: {
                        row("Spectrogram", "waveform", "\(listener.palette.title) · \(listener.spectrogramSeconds) s")
                    }
                    NavigationLink { page("Audio") { audio } } label: {
                        row("Audio", "mic", micSummary)
                    }
                    NavigationLink { page("Listening") { listening; oneTouch } } label: {
                        row("Listening", "timer", listeningSummary)
                    }
                    if !listener.mutedNames.isEmpty {
                        NavigationLink { page("Never show") { muted } } label: {
                            row("Never show", "eye.slash", "\(listener.mutedNames.count)")
                        }
                    }
                }
                about
            }.themedRows() }.themedList()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(isPresented: $showLocation) { page("Location & season") { location; ebirdSection } }
            .navigationDestination(item: $showPage) { p in
                switch p {
                case "Inference": page(p) { inference; humanGuard }
                case "Spectrogram": page(p) { spectrogram; spectrogramTuning }
                default: page("Audio") { audio }
                }
            }
            .onAppear { inputs = AudioCapture.inputs(); listener.updateContext() }
        }
    }

    private func page<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Form { Group { content() }.themedRows() }.themedList().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ symbol: String, _ value: String) -> some View {
        LabeledContent { Text(value).lineLimit(1) } label: { Label(title, systemImage: symbol) }
    }

    private var listenSummary: String {
        let on = ListenGroup.allCases.filter { listener.policy.setting($0).enabled }
        if on.count == ListenGroup.allCases.count { return "Everything" }
        if on.isEmpty { return "Nothing" }
        return "\(on.count) of \(ListenGroup.allCases.count)"
    }

    private var locationSummary: String {
        let mode = ["off": "Off", "flag": "Flag", "hide": "Hide"][listener.policy.rangeMode.rawValue] ?? ""
        return listener.ebird.hasKey && listener.policy.rangeMode != .off ? "\(mode) · eBird" : mode
    }
    private var micSummary: String {
        let name = inputs.first { $0.uid == listener.inputUID }?.portName ?? "Automatic"
        return ([name] + (listener.gainDB > 0 ? ["+\(Int(listener.gainDB)) dB"] : []) + (listener.rumbleFilter > 0 ? ["\(Int(listener.rumbleFilter)) Hz"] : [])).joined(separator: " · ")
    }
    private var inferenceSummary: String {
        "\(Int((listener.policy.shown * 100).rounded()))% · every \(Self.seconds(listener.scoreInterval))"
    }
    private static func seconds(_ s: Double) -> String { s == s.rounded() ? "\(Int(s)) s" : String(format: "%.1f s", s) }
    private var listeningSummary: String {
        let stop = listener.stopAfterMinutes == 0 ? "no time limit" : listener.stopAfterMinutes < 60 ? "stops after \(listener.stopAfterMinutes) min" : "stops after \(listener.stopAfterMinutes / 60) h"
        return "\(listener.idMode == .auto ? "Auto" : "Manual") · \(stop)"
    }

    // MARK: Detection

    private var presetBinding: Binding<Preset?> {
        Binding(get: { listener.policy.preset }, set: { if let p = $0 { listener.policy.apply(p) } })
    }

    private var modelBlurb: String {
        switch listener.model {
        case .perch: "Perch 2.0 alone: best on distant, noisy audio."
        case .birdnet: "BirdNET+ 3.0 alone: best on close, clean recordings."
        case .both: "Both listen; an ID counts when they agree or either is very sure. Catches the most with the least junk."
        }
    }

    private var detection: some View {
        Section {
            if listener.birdnetAvailable {
                @Bindable var listener = listener
                Picker("Model", selection: $listener.model) {
                    Text("Perch").tag(Fusion.Model.perch); Text("BirdNET+").tag(Fusion.Model.birdnet); Text("Both").tag(Fusion.Model.both)
                }
                .pickerStyle(.segmented)
            }
            Picker("How picky", selection: presetBinding) {
                ForEach(Preset.allCases, id: \.self) { Text($0.title).tag(Preset?.some($0)) }
                if listener.policy.preset == nil { Text("Custom").tag(Preset?.none) }
            }
            .pickerStyle(.segmented)
            Picker("Hear it for", selection: Binding(get: { listener.confirmSeconds }, set: { listener.confirmSeconds = $0 })) {
                Text("Off").tag(1); Text("2 s").tag(2); Text("3 s").tag(3); Text("4 s").tag(4)
            }
            Toggle("Show maybes", isOn: Binding(get: { listener.showMaybes }, set: { listener.showMaybes = $0 }))
        } header: { Text("Detection") } footer: {
            Text((listener.birdnetAvailable ? modelBlurb + " " : "") + (listener.policy.preset?.blurb ?? "You've fine-tuned the thresholds. Pick a preset to reset them.")
                 + " \"Hear it for\" is how long a new species must keep calling before it's logged: longer means fewer one-off mistakes; Off logs the first second that clears the bar.")
        }
    }

    // MARK: Inference

    /// The numbers behind "How picky": one bar for everything, how often Hark checks, how long it must keep hearing.
    private var inference: some View {
        @Bindable var listener = listener
        return Section {
            VStack(alignment: .leading) {
                HStack { Text("Confidence threshold"); Spacer(); Text("\(Int((listener.policy.shown * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: Binding(get: { Double(listener.policy.shown) }, set: { listener.policy.apply(shown: Float($0)) }), in: 0.5...0.98, step: 0.01)
            }
            VStack(alignment: .leading) {
                HStack { Text("Check every"); Spacer(); Text(Self.seconds(listener.scoreInterval) + String(format: " · %.2f Hz", 1 / listener.scoreInterval)).monospacedDigit().foregroundStyle(.secondary) }
                // the slider runs slow -> fast, left to right
                Slider(value: Binding(get: { 5.5 - listener.scoreInterval }, set: { listener.scoreInterval = 5.5 - $0 }), in: 0.5...5, step: 0.5)
            }
            Picker("Hear it for", selection: Binding(get: { listener.confirmSeconds }, set: { listener.confirmSeconds = $0 })) {
                Text("Off").tag(1); Text("2 s").tag(2); Text("3 s").tag(3); Text("4 s").tag(4)
            }
            NavigationLink("Thresholds by group") { ThresholdsView() }
            if listener.lastInferenceMs > 0 {
                LabeledContent("Last check took", value: String(format: "%.0f ms", listener.lastInferenceMs))
            }
        } footer: {
            Text("Confidence threshold is the bar an ID must clear to be logged, in the same percentages as everywhere else in Hark (insects and \"other\" sit a little higher); it's the slider behind How picky. Check every: how often Hark scores the last 5 seconds. Once a second is the default; every 2 to 5 seconds is easier on the battery for a long walk and still hears everything, since each check covers 5 seconds. The models' own windows are fixed (Perch 5 s, BirdNET+ 3 s) and can't be changed.")
        }
    }

    private var humanGuard: some View {
        @Bindable var listener = listener
        return Section {
            Picker("Voices & music guard", selection: $listener.policy.humanGuard) {
                ForEach(HumanGuard.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Count breathing and coughs too", isOn: $listener.policy.guardBodySounds).disabled(listener.policy.humanGuard == .off)
        } header: { Text("People sounds") } footer: {
            Text("When a stretch of sound is mostly talking, singing or music, Hark only accepts an animal ID it is very sure of, so a song on the radio doesn't become a bird. Standard is how Hark has always worked. Light waits for more of it before stepping in; Strong steps in sooner; Off trusts every ID. The switch adds breathing, coughs, sneezes and whispers to what trips the guard: useful with the phone near your face, but it can cost you a quiet bird while you catch your breath. Needs Perch (it's the model that hears people).")
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
        } footer: { Text("Switch off what you don't want to hear about. Fine-tune sets each group's own bar.") }
    }

    private func caption(_ g: ListenGroup, _ s: GroupSetting) -> String {
        g == .sound ? "Shows at \(s.threshold.shownPercent)% · never logged"
                    : "Logs at \(s.threshold.shownPercent)%" + (listener.showMaybes ? " · maybes from \(listener.policy.maybeFloor(g).shownPercent)%" : "")
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
        } footer: {
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
            VStack(alignment: .leading) {
                HStack { Text("Height"); Spacer(); Text(listener.spectrogramHeight >= 0.97 ? "Full screen" : "\(Int((listener.spectrogramHeight * 100).rounded()))% of the screen").foregroundStyle(.secondary) }
                Slider(value: $listener.spectrogramHeight, in: 0.2...1, step: 0.04)
            }
            Toggle("Frequency labels", isOn: $listener.frequencyLabels)
            Toggle("Critters on the calls", isOn: $listener.critters)
        } footer: {
            Text("Critters pin each logged species on its call as it scrolls by; with the spectrogram full screen they collect on the left. Height is how much of the screen the spectrogram takes when the phone is upright; all the way up is full screen, and the arrows button on the spectrogram switches to full screen and back any time. Owling is all red, to keep your night vision on an owl prowl. Punchy contrast makes faint calls stand out but also shows more background. Colors and contrast don't change what Hark identifies.")
        }
    }

    private var spectrogramTuning: some View {
        @Bindable var listener = listener
        return Section {
            Picker("FFT size", selection: $listener.fftSize) {
                Text("512").tag(512); Text("1024").tag(1024); Text("2048").tag(2048)
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                HStack { Text("Top frequency"); Spacer(); Text("\(Int(listener.topKHz)) kHz").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $listener.topKHz, in: 4...16, step: 1)
            }
            Toggle("Fade steady background", isOn: $listener.fadeBackground)
            Picker("Quality", selection: $listener.quality) {
                ForEach(SpectrogramQuality.allCases) { Text($0.title).tag($0) }
            }
            Button("Reset tuning") {
                listener.fftSize = 1024; listener.topKHz = 15; listener.fadeBackground = true; listener.quality = .standard
                listener.spectrogramHeight = Listener.standardHeight
            }
        } header: { Text("Tuning") } footer: {
            Text("FFT size trades time for pitch: 512 keeps fast trills and chips crisp, 2048 separates close harmonics but smears quick notes. Top frequency: most birdsong is under 10 kHz, so a lower ceiling gives it more room; 16 kHz is everything the microphone feed carries. Brightness is always logarithmic (decibels), which is what lets faint calls show at all. Fade steady background also dims each pitch's constant noise (wind, traffic, a furnace); turn it off to see the true shape of the sound, hums and all. For faint calls, Punchy contrast does the most. Quality: High draws every column and smooths more, Battery saver draws fewer at half the frame rate. None of this changes what Hark identifies.")
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
            VStack(alignment: .leading) {
                HStack { Text("Gain"); Spacer(); Text(listener.gainDB > 0 ? "+\(Int(listener.gainDB)) dB" : "Off").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $listener.gainDB, in: 0...36, step: 3)
            }
            VStack(alignment: .leading) {
                HStack { Text("High-pass filter"); Spacer(); Text(listener.rumbleFilter > 0 ? "\(Int(listener.rumbleFilter)) Hz" : "Off").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $listener.rumbleFilter, in: 0...1000, step: 10)
            }
        } footer: {
            Text("Plug in a USB-C or wired mic and pick it here (applies the next time you start listening). Gain makes everything louder before Hark hears it, saves it or draws it. The models don't mind quiet audio until it gets very quiet, and then they go deaf fast: if the level bar barely moves (a low-output external mic, calls from far off), add gain until it does. Too much clips loud, close sounds. The high-pass filter cuts everything below the frequency you set: 80 Hz trims wind and handling noise, 200 Hz road rumble. Above about 300 Hz it starts taking owls, doves, grouse and bitterns with it.")
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
        } footer: {
            Text("Auto identifies everything it hears and keeps logging with the screen locked (shown on the Lock Screen and Dynamic Island; a new species buzzes the phone). Manual only identifies what you select on the spectrogram. Either way, touch the spectrogram to pick out a call from the last minute. The time limit is for Live; a point count stops at its own time and a survey runs until you stop it. Pick the mode with the button on the spectrogram.")
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
            LabeledContent("Model", value: ["perch": "Perch 2.0", "birdnet": "BirdNET+ 3.0", "both": "Perch 2.0 + BirdNET+ 3.0"][listener.model.rawValue] ?? "")
            if listener.lastInferenceMs > 0 {
                LabeledContent("Speed", value: String(format: "%.0f ms per window", listener.lastInferenceMs))
            }
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            NavigationLink("Acknowledgements") { AcknowledgementsView() }
        } header: { Text("About") } footer: {
            Text("Everything runs on this iPhone. Audio never leaves it.")
        }
    }
}

/// Per-group sliders, for people who want them.
struct ThresholdsView: View {
    @Environment(Listener.self) private var listener
    var body: some View {
        Form { Group {
            Section {
                ForEach(ListenGroup.allCases, id: \.self) { g in
                    let s = listener.policy.setting(g)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label { Text(g.title) } icon: { TaxonIcon(group: g.taxon, size: 26) }
                            Spacer()
                            Text("\(s.threshold.shownPercent)%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        // the slider moves in the percentages people see; the policy keeps Perch's scale
                        Slider(value: Binding(get: { Fusion.display(s.threshold) },
                                              set: { v in listener.policy.set(g, GroupSetting(enabled: s.enabled, threshold: Fusion.fromDisplay(v))) }),
                               in: 0.5...0.98, step: 0.01)
                            .disabled(!s.enabled)
                    }
                    .opacity(s.enabled ? 1 : 0.4)
                }
            } footer: {
                Text("A sound at or above its group's bar is logged; with Show maybes on, a little under it shows as a maybe you can log by hand. Raise a group that gives you wrong IDs (insects are the usual suspect); lower one that misses quiet calls. Percentages read like BirdNET's: 85% is a confident ID.")
            }
            Section {
                ForEach(Preset.allCases, id: \.self) { p in
                    Button("Reset to \(p.title)") { listener.policy.apply(p) }
                }
            }
        }.themedRows() }.themedList()
        .navigationTitle("Thresholds")
        .navigationBarTitleDisplayMode(.inline)
    }
}
