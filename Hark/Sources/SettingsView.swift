import SwiftUI
import AVFoundation
import HarkCore

struct SettingsView: View {
    @Environment(Listener.self) private var listener
    @Environment(\.dismiss) private var dismiss
    @State private var inputs: [AVAudioSessionPortDescription] = []
    @State private var confirmReset = false
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
                } header: { Text("Look") } footer: {
                    Text("\(AppTheme.stored.title): \(AppTheme.stored.blurb) Each look brings its own spectrogram colors; change those under Spectrogram.")
                }
                Section {
                    Picker("Names", selection: Binding(get: { NameBook.shared.style }, set: { NameBook.shared.style = $0 })) {
                        ForEach(NameBook.Style.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("Which name leads. Give a species your own name on its page in the Log.")
                }
                detection
                Section {
                    NavigationLink { page("Listen for") { listenFor } } label: {
                        row("Listen for", "pawprint", listenSummary)
                    }
                    NavigationLink { page("Location & season") { location; ebirdSection } } label: {
                        row("Location & season", "location", locationSummary)
                    }
                    NavigationLink { page("Detection tuning") { inference; humanGuard } } label: {
                        row("Detection tuning", "dial.medium", inferenceSummary)
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
                case "Inference": page("Detection tuning") { inference; humanGuard }
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
        return (listener.keepScreenOn ? "Screen on" : "Screen sleeps") + " · " + stop
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
        @Bindable var listener = listener
        return Section {
            if listener.birdnetAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    SettingLabel("Model", help: "Which model identifies what Hark hears.\n\nPerch 2.0: best on distant, noisy audio, and the only one that knows frogs, insects and most mammals well.\n\nBirdNET+ 3.0: best on close, clean recordings of birds.\n\nBoth: the two listen together, and an ID counts when they agree or when either is very sure. It catches the most with the fewest wrong IDs, and costs a little more battery.",
                                 standard: "Both", changed: listener.model != .both) { listener.model = .both }
                    Picker("Model", selection: $listener.model) {
                        Text("Perch").tag(Fusion.Model.perch); Text("BirdNET+").tag(Fusion.Model.birdnet); Text("Both").tag(Fusion.Model.both)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingLabel("How picky", help: "How confident Hark must be before it logs an ID.\n\nSensitive (70%): catches faint and distant calls, with more wrong guesses.\n\nBalanced (85%): confident IDs. A good default.\n\nStrict (92%): only the surest. Misses some real calls, rarely wrong.\n\nCustom means you've moved the sliders under Detection tuning or Listen for; picking a preset puts them back.",
                             standard: "Balanced", changed: listener.policy.preset != .balanced) { listener.policy.apply(.balanced) }
                Picker("How picky", selection: presetBinding) {
                    ForEach(Preset.allCases, id: \.self) { Text($0.title).tag(Preset?.some($0)) }
                    if listener.policy.preset == nil { Text("Custom").tag(Preset?.none) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            hearItFor
            Toggle(isOn: $listener.showMaybes) {
                SettingLabel("Show maybes", help: "A maybe is a species Hark half-heard: under the bar, but not nothing. On, maybes show faintly under Hearing now with a \"?\" and you can log one by hand. They're never logged automatically.\n\nIn a quiet room maybes are mostly noise, so this starts off. Turn it on when you're trying to pull a faint or distant call out.",
                             standard: "Off", changed: listener.showMaybes) { listener.showMaybes = false }
            }
        } header: { Text("Detection") } footer: { Text("Tap any ⓘ for what a setting does and how to put it back.") }
    }

    private var hearItFor: some View {
        Picker(selection: Binding(get: { listener.confirmSeconds }, set: { listener.confirmSeconds = $0 })) {
            Text("Off").tag(1); Text("2 s").tag(2); Text("3 s").tag(3); Text("4 s").tag(4)
        } label: {
            SettingLabel("Hear it for", help: "How long a new species must keep being heard before it's logged.\n\nLonger means fewer one-off mistakes from a single odd noise, and a slightly slower first ID. A bird that calls once, briefly, can be missed: touch the spectrogram to pick that one out by hand.\n\nOff logs the first check that clears the bar.",
                         standard: "2 s", changed: listener.confirmSeconds != 2) { listener.confirmSeconds = 2 }
        }
    }

    // MARK: Inference

    /// The numbers behind "How picky": one bar for everything, how often Hark checks, how long it must keep hearing.
    private var inference: some View {
        @Bindable var listener = listener
        let pct = Int((listener.policy.shown * 100).rounded())
        return Group {
            Section {
                VStack(alignment: .leading) {
                    SettingLabel("Confidence threshold", value: "\(pct)%", help: "The bar an ID must clear to be logged, as the same percentage you see next to every ID. It's the slider behind How picky.\n\nLower (toward 50%): more faint and distant calls, more wrong IDs.\n\nHigher (toward 98%): fewer wrong IDs, more real calls missed.\n\n70% is Sensitive, 85% Balanced, 92% Strict. Insects and \"other animals\" always sit a little higher, since the models are least reliable there. Each group can have its own bar under Thresholds by group.",
                                 standard: "85%", changed: listener.policy.preset != .balanced) { listener.policy.apply(.balanced) }
                    Slider(value: Binding(get: { Double(listener.policy.shown) }, set: { listener.policy.apply(shown: Float($0)) }), in: 0.5...0.98, step: 0.01)
                        .accessibilityValue("\(pct) percent")
                }
                VStack(alignment: .leading) {
                    SettingLabel("Check every", value: Self.seconds(listener.scoreInterval) + String(format: " · %.2f Hz", 1 / listener.scoreInterval),
                                 help: "How often Hark scores the last 5 seconds of sound while listening. Right is faster.\n\nOnce a second (1 Hz) is the default. Every 2 to 5 seconds uses less battery on a long walk and still hears everything, because each check covers 5 seconds; a new ID just shows up a few seconds later. Twice a second catches a brief call a beat sooner and uses more battery.\n\nThe models' own windows are fixed (Perch 5 s, BirdNET+ 3 s); this is how often they run, not how much they hear.",
                                 standard: "1 s (1 Hz)", changed: listener.scoreInterval != 1) { listener.scoreInterval = 1 }
                    // the slider runs slow -> fast, left to right
                    Slider(value: Binding(get: { 5.5 - listener.scoreInterval }, set: { listener.scoreInterval = 5.5 - $0 }), in: 0.5...5, step: 0.5)
                        .accessibilityValue("every \(Self.seconds(listener.scoreInterval))")
                }
                hearItFor
                NavigationLink("Thresholds by group") { ThresholdsView() }
            }
            Section {
                if listener.lastInferenceMs > 0 {
                    LabeledContent("Last check took", value: String(format: "%.0f ms", listener.lastInferenceMs))
                }
                Toggle(isOn: $listener.showSpeed) {
                    SettingLabel("Show speed while listening", help: "Puts the time each check takes, in milliseconds, next to the microphone level on the Listen screen.\n\nWith both models on a recent iPhone it's a few tens of milliseconds. If it climbs toward your Check every time, the phone is hot or busy and checks are running back to back.",
                                 standard: "Off", changed: listener.showSpeed) { listener.showSpeed = false }
                }
            } header: { Text("Speed") }
        }
    }

    private var humanGuard: some View {
        @Bindable var listener = listener
        return Group {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    SettingLabel("Voices & music guard", help: "When a stretch of sound is mostly talking, singing or music, Hark only accepts an animal ID it is very sure of, so a song on the radio doesn't become a bird. A line under Hearing now tells you when it has stepped in.\n\nStandard: how Hark has always worked.\nLight: waits for more voice or music before stepping in.\nStrong: steps in sooner.\nOff: trusts every ID, whatever else is in the room.\n\nNeeds Perch (it's the model that hears people), so it does nothing with BirdNET+ alone.",
                                 standard: "Standard", changed: listener.policy.humanGuard != .standard) { listener.policy.humanGuard = .standard }
                    Picker("Voices & music guard", selection: $listener.policy.humanGuard) {
                        ForEach(HumanGuard.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            } header: { Text("People sounds") } footer: {
                Text("Hark doesn't hide what it hears: your own cough, breathing or footsteps show up under Hearing now like any other non-animal sound (never logged). Don't want to see one? Swipe left on it and choose Never show. Don't want any of them? Turn off Non-animal sounds under Listen for.")
            }
            resetPage("Detection tuning") {
                listener.policy.apply(.balanced); listener.policy.humanGuard = .standard
                listener.scoreInterval = 1; listener.confirmSeconds = 2; listener.showSpeed = false
            }
        }
    }

    /// The bottom of a page: everything on it back to how Hark came.
    private func resetPage(_ name: String, _ action: @escaping () -> Void) -> some View {
        Section { Button("Reset \(name) to defaults", role: .destructive, action: action) }
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
            VStack(alignment: .leading, spacing: 8) {
                SettingLabel("Unexpected species", help: "What to do with a confident ID of a species that doesn't belong where you are at this time of year.\n\nFlag: shown as \"unusual\" and only logged if you tap it.\nHide: dropped without a word.\nOff: logged like any other.\n\nHark checks the BirdNET geomodel (where each species is, week by week) and GBIF records within about 150 km. Species you've confirmed near here, your patch, are never flagged.",
                             standard: "Flag", changed: listener.policy.rangeMode != .flag) { listener.policy.rangeMode = .flag }
                Picker("Unexpected species", selection: $listener.policy.rangeMode) {
                    Text("Off").tag(RangeMode.off); Text("Flag").tag(RangeMode.flag); Text("Hide").tag(RangeMode.hide)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            if listener.policy.rangeMode != .off {
                if let c = listener.context {
                    if listener.geoAvailable { LabeledContent("Expected this week", value: "\(c.expectedThisWeek.formatted()) species") }
                    if let r = listener.localRange { LabeledContent("Ever recorded nearby", value: "\(r.speciesHere.formatted()) species") }
                    LabeledContent("Your patch", value: listener.patch.isEmpty ? "None yet" : "\(listener.patch.count) species")
                } else {
                    LabeledContent("Status", value: listener.rangeAvailable ? "Waiting for location" : "No range data in this build")
                }
            }
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
            VStack(alignment: .leading, spacing: 8) {
                SettingLabel("Time shown", help: "How many seconds of sound fit across the spectrogram when the phone is upright (on its side it shows proportionally more).\n\n5 s spreads each call out so you can see its shape. 30 s shows the pattern of who is calling when, and everything scrolls slowly. Touching the spectrogram always reaches back a full minute, whatever this is set to.",
                             standard: "10 s", changed: listener.spectrogramSeconds != 10) { listener.spectrogramSeconds = 10 }
                Picker("Time shown", selection: $listener.spectrogramSeconds) {
                    Text("5 s").tag(5); Text("10 s").tag(10); Text("15 s").tag(15); Text("30 s").tag(30)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading) {
                SettingLabel("Contrast", value: listener.contrast < 0.34 ? "Soft" : listener.contrast > 0.67 ? "Punchy" : "Medium",
                             help: "How loud a sound must be, above the background, to reach full brightness.\n\nSoft spreads the colors over about 54 dB: loud and quiet calls look different, faint ones stay dim.\n\nPunchy squeezes them into about 24 dB: faint calls stand out, and so does more of the background.\n\nThis is the setting to reach for when a quiet call is hard to see.",
                             standard: "Medium", changed: abs(listener.contrast - 0.6) > 0.01) { listener.contrast = 0.6 }
                Slider(value: $listener.contrast, in: 0...1)
                    .accessibilityValue(listener.contrast < 0.34 ? "Soft" : listener.contrast > 0.67 ? "Punchy" : "Medium")
            }
            VStack(alignment: .leading) {
                SettingLabel("Height", value: listener.spectrogramHeight >= 0.97 ? "Full screen" : "\(Int((listener.spectrogramHeight * 100).rounded()))%",
                             help: "How much of the screen the spectrogram takes when the phone is upright, as a share of the space above the buttons.\n\nAll the way right is full screen: no list, with what's being heard shown over the spectrogram. The arrows button on the spectrogram switches to full screen and back any time without changing this.",
                             standard: "32%", changed: abs(listener.spectrogramHeight - Listener.standardHeight) > 0.01) { listener.spectrogramHeight = Listener.standardHeight }
                Slider(value: $listener.spectrogramHeight, in: 0.2...1, step: 0.04)
                    .accessibilityValue(listener.spectrogramHeight >= 0.97 ? "Full screen" : "\(Int((listener.spectrogramHeight * 100).rounded())) percent")
            }
            Toggle(isOn: $listener.frequencyLabels) {
                SettingLabel("Frequency labels", help: "The 1k, 2k, 4k, 8k marks down the left edge: pitch in kilohertz. A Great Horned Owl hoots near 0.3k, a robin sings around 2 to 4k, a Golden-crowned Kinglet is up near 8k.",
                             standard: "On", changed: !listener.frequencyLabels) { listener.frequencyLabels = true }
            }
            Toggle(isOn: $listener.critters) {
                SettingLabel("Critters on the calls", help: "Pins each logged species on the loudest part of its call as it scrolls by, so you can see which sound was which. With the spectrogram full screen they collect on the left as they scroll off.",
                             standard: "On", changed: !listener.critters) { listener.critters = true }
            }
        } footer: {
            Text("Nothing on this page changes what Hark identifies; it's only how the sound is drawn.")
        }
    }

    private var spectrogramTuning: some View {
        @Bindable var listener = listener
        return Group {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    SettingLabel("FFT size", help: "How many samples each column of the spectrogram is computed from. It trades sharpness in time for sharpness in pitch.\n\n512 (16 ms): fast trills, chips and rattles stay crisp; close pitches blur together.\n\n1024 (32 ms): a balance.\n\n2048 (64 ms): close harmonics and steady whistles separate cleanly; quick notes smear sideways.",
                                 standard: "1024", changed: listener.fftSize != 1024) { listener.fftSize = 1024 }
                    Picker("FFT size", selection: $listener.fftSize) {
                        Text("512").tag(512); Text("1024").tag(1024); Text("2048").tag(2048)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                VStack(alignment: .leading) {
                    SettingLabel("Top frequency", value: "\(Int(listener.topKHz)) kHz", help: "The highest pitch drawn. The bottom is always 150 Hz.\n\nMost birdsong is under 10 kHz, so a lower ceiling gives it more of the height. 4 to 6 kHz suits owls, doves, frogs and waterfowl. 16 kHz is everything the audio carries, and where some insects and the highest warblers live.\n\nSounds above the ceiling are still heard and identified; they just aren't drawn.",
                                 standard: "15 kHz", changed: listener.topKHz != 15) { listener.topKHz = 15 }
                    Slider(value: $listener.topKHz, in: 4...16, step: 1).accessibilityValue("\(Int(listener.topKHz)) kilohertz")
                }
                Toggle(isOn: $listener.fadeBackground) {
                    SettingLabel("Fade steady background", help: "On: each pitch dims its own constant noise (wind, traffic, a furnace, the natural low-end rumble), so calls stand out against black.\n\nOff: the true shape of the sound, hums and all, with one brightness level for every pitch. Useful for seeing what's actually in the background, or a steady insect chorus that fading would hide.\n\nBrightness is logarithmic (decibels) either way, which is what lets faint calls show at all.",
                                 standard: "On", changed: !listener.fadeBackground) { listener.fadeBackground = true }
                }
                Picker(selection: $listener.quality) {
                    ForEach(SpectrogramQuality.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingLabel("Quality", help: "How much work goes into drawing the live spectrogram.\n\nHigh: every column drawn, smoother scaling. Sharpest, most battery.\n\nStandard: neighboring columns share a pixel on longer time spans.\n\nBattery saver: half the columns at half the frame rate (30 a second). For long sessions with the screen on.",
                                 standard: "Standard", changed: listener.quality != .standard) { listener.quality = .standard }
                }
            } header: { Text("Tuning") }
            resetPage("Spectrogram") {
                listener.spectrogramSeconds = 10; listener.contrast = 0.6; listener.spectrogramHeight = Listener.standardHeight
                listener.frequencyLabels = true; listener.critters = true
                listener.fftSize = 1024; listener.topKHz = 15; listener.fadeBackground = true; listener.quality = .standard
            }
        }
    }

    // MARK: Audio

    private var audio: some View {
        @Bindable var listener = listener
        return Group {
            Section {
                Picker(selection: $listener.inputUID) {
                    Text("Automatic").tag(String?.none)
                    ForEach(inputs, id: \.uid) { p in Text(p.portName).tag(String?.some(p.uid)) }
                } label: {
                    SettingLabel("Microphone", help: "Which microphone Hark listens through. Automatic is the iPhone's own, or whatever iOS picks when something is plugged in.\n\nPlug in a USB-C or wired mic and choose it here. It applies the next time you start listening.",
                                 standard: "Automatic", changed: listener.inputUID != nil) { listener.inputUID = nil }
                }
                VStack(alignment: .leading) {
                    SettingLabel("Gain", value: listener.gainDB > 0 ? "+\(Int(listener.gainDB)) dB" : "Off",
                                 help: "Makes everything louder before Hark hears it, saves it or draws it. Each 6 dB doubles the level.\n\nThe models don't mind quiet audio until it gets very quiet, and then they go deaf fast. If the level bar on the Listen screen barely moves (a low-output external mic, calls from far off), add gain until it does.\n\nIf the bar is already moving, gain won't help IDs, and too much clips loud, close sounds.",
                                 standard: "Off", changed: listener.gainDB != 0) { listener.gainDB = 0 }
                    Slider(value: $listener.gainDB, in: 0...36, step: 3).accessibilityValue("\(Int(listener.gainDB)) decibels")
                }
                VStack(alignment: .leading) {
                    SettingLabel("High-pass filter", value: listener.rumbleFilter > 0 ? "\(Int(listener.rumbleFilter)) Hz" : "Off",
                                 help: "Cuts every sound below the frequency you set, before Hark hears or draws it.\n\n80 Hz: wind and handling noise.\n200 Hz: road rumble.\n300 Hz and up: you start losing the lowest voices (owls, doves, grouse, bitterns).\n1,000 Hz: heavy wind or surf, and most of those birds go with it.\n\nLeave it off unless low noise is drowning things out.",
                                 standard: "Off", changed: listener.rumbleFilter != 0) { listener.rumbleFilter = 0 }
                    Slider(value: $listener.rumbleFilter, in: 0...1000, step: 10).accessibilityValue("\(Int(listener.rumbleFilter)) hertz")
                }
            }
            resetPage("Audio") { listener.inputUID = nil; listener.gainDB = 0; listener.rumbleFilter = 0 }
        }
    }

    // MARK: Listening

    private var listening: some View {
        @Bindable var listener = listener
        return Section {
            Toggle(isOn: $listener.keepScreenOn) {
                SettingLabel("Keep screen on", help: "Stops the phone from dimming and locking while Hark listens, so you can watch the spectrogram.\n\nOff, the phone locks as usual and Hark carries on in the background: IDs show on the Lock Screen and Dynamic Island, and a new species buzzes. That's the way to save battery on a long walk.",
                             standard: "On", changed: !listener.keepScreenOn) { listener.keepScreenOn = true }
            }
            Picker(selection: $listener.stopAfterMinutes) {
                Text("15 min").tag(15); Text("30 min").tag(30); Text("1 hour").tag(60)
                Text("2 hours").tag(120); Text("4 hours").tag(240); Text("Never").tag(0)
            } label: {
                SettingLabel("Stop listening after", help: "A safety net for Live and Manual: Hark stops itself after this long, so a forgotten session doesn't run the battery down in your pocket.\n\nIt doesn't apply to a point count (which stops at its own time) or a survey (which runs until you stop it).",
                             standard: "1 hour", changed: listener.stopAfterMinutes != 60) { listener.stopAfterMinutes = 60 }
            }
        } footer: {
            Text("Pick what the big button does (Live, Manual, Point count, Survey, Recordings) in the row above it on the Listen screen.")
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
            Button("Reset all settings", role: .destructive) { confirmReset = true }
                .confirmationDialog("Put every setting back the way Hark came?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset settings", role: .destructive) { listener.resetSettings() }
                } message: { Text("Your log, names, never-show list, eBird key and look stay as they are.") }
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

/// A setting's name with its ⓘ: what it does, what it costs you, what the numbers mean, what it shipped as, and a
/// way back to that. The ⓘ fills in when the setting has been changed, so you can see at a glance what you've touched.
struct SettingLabel: View {
    let title: String
    var value: String?
    let help: String
    var standard: String?
    var changed = false
    var reset: (() -> Void)?
    @State private var show = false

    init(_ title: String, value: String? = nil, help: String, standard: String? = nil, changed: Bool = false, reset: (() -> Void)? = nil) {
        self.title = title; self.value = value; self.help = help; self.standard = standard; self.changed = changed; self.reset = reset
        let args = ProcessInfo.processInfo.arguments      // screenshot aid: -showinfo Gain
        if let i = args.firstIndex(of: "-showinfo"), i + 1 < args.count, args[i + 1] == title { _show = State(initialValue: true) }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Button { show = true } label: {
                Image(systemName: changed ? "info.circle.fill" : "info.circle")
                    .foregroundStyle(changed ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("About \(title)" + (changed ? ", changed from the default" : ""))
            .popover(isPresented: $show) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(.headline)
                        Text(help).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if let standard {
                            Divider()
                            HStack {
                                Text("Default: \(standard)").font(.callout).foregroundStyle(.secondary)
                                Spacer()
                                if let reset {
                                    Button(changed ? "Reset" : "At default") { reset(); show = false }
                                        .buttonStyle(.bordered).disabled(!changed)
                                }
                            }
                        }
                    }
                    .padding(18)
                }
                .frame(idealWidth: 320, maxHeight: 460)
                .presentationCompactAdaptation(.popover)
            }
            if let value {
                Spacer(minLength: 4)
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
