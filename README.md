# Hark (working name)

Free, noncommercial iPhone app: pull it out, hear something, find out what it is. Runs Google's Perch 2.0 on-device
(Neural Engine) for birds, frogs, insects and mammals (14,795 classes). Every ID is logged with time and place;
"I saw it" marks the ones you verified.

## Layout
- `HarkCore/`: Swift package, testable on the Mac (`cd HarkCore && swift test`). RingBuffer, Scoring (softmax,
  optional rest logit for regional slices), LabelTable, PerchClassifier (Core ML), DetectionTracker (occurrences with 60 s gaps).
  `GoldenParityTests` runs the real model on 12 backyard windows and requires TF-reference top-1 on ANE and GPU.
- `Hark/`: SwiftUI app.
  - Listen: AudioCapture (AVAudioEngine, .measurement, -> 32 kHz mono), Listener (scores the newest 5 s once a
    second; DetectionPolicy triage -> hits are logged, maybes / unusual-here shown for logging by hand), live FFT
    spectrogram (SpectrogramDSP, independent of Perch), touch-to-select (touch freezes the last 60 s, drag picks a call, Perch scores it; Auto vs Manual ID mode).
  - Every logged detection keeps a clip (ClipStore, AAC m4a). ListeningSession records each listen + its route.
  - Log: Timeline / Sessions (route map + species timeline chart) / Species (life list, growth curve, species pages
    with time-of-day + month charts) / Map. Search + group filter.
  - Walk mode: background audio + location, Live Activity (LiveActivityController) with Stop, buzz on new species,
    auto-stop setting. Perch runs on CPU+ANE only (no GPU in background).
- `Hark/Shared/`: compiled into the app and HarkWidgets. StartListeningIntent (Action Button / Control Center /
  Siri), StopListeningIntent (Live Activity), ListeningAttributes, WidgetSnapshot (App Group JSON for widgets).
- `HarkWidgets/`: widget extension. Today widget (small/medium/Lock Screen), Start Listening control, Live Activity.
- `Models/Perch.mlpackage`: git-ignored. Build it with ~/working/perch-spike (`./build.sh`), then
  `cp -R ../perch-spike/models/perch_v2_full_fp16.mlpackage Models/Perch.mlpackage`.
- `tools/gbif_ranges.py`: location filter data. Per Perch species, GBIF backbone match + global density map
  (1.40625-degree cells, >= 2 records, solid cells also mark their neighbors) -> `Hark/Resources/ranges.bin`.
  `fetch` takes ~70 min (cached/resumable in tools/data/gbif/), `build` is instant. Credit GBIF.org in the app.
- `tools/make_labels.py`: label table from Perch labels + OpenFauna names/classes (data copied from birdnet-go's
  vendored snapshot on CORTEX into tools/data/). OpenFauna's license still needs checking before any public release.

## Location + season

`LocalContext` (HarkCore) combines, most trusted first: eBird reports within 25 km / 30 days (user's own API key,
Keychain), your patch (confirmed, or logged on 3+ days, within 10 km), the BirdNET+ Geomodel V3.0.4 (Apache 2.0;
lat/lon/week -> 14,082 species; 12,258 Perch labels mapped; all 48 weeks run so "out of season" differs from
"never here"), then the GBIF range map. Rebuild the geomodel + map: `~/working/perch-spike/.venv/bin/python
tools/convert_geomodel.py` (writes Models/Geo.mlpackage, git-ignored, and Hark/Resources/geo_map.bin).

## Build / install (headless)
```
xcodegen generate
xcodebuild -project Hark.xcodeproj -scheme Hark -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> DerivedData/Build/Products/Release-iphoneos/Hark.app
xcrun devicectl device process launch --console --device <udid> dev.ducktyping.hark -selftest   # ANE parity + timing
```
Launch args (testing/screenshots): `-feedfile a.wav,b.wav` (stream files instead of the mic), `-select` (freeze + identify 9 s in), `-settingslocation` (with -settings: scroll to Location & season), `-resettips` (first-run tips again), `-notips`,
`-settings`, `-logtab`, `-opensession`, `-selftest` (golden windows on ANE/GPU/CPU, prints HARK-SELFTEST lines), `-autolisten` (start listening on launch).
