# Hark: Listen Closer

Free, noncommercial iPhone app: pull it out, hear something, find out what it is. Two neural networks, Google
DeepMind's Perch 2.0 and the BirdNET team's BirdNET+ 3.0, listen together on the iPhone's Neural Engine, and the
BirdNET+ geomodel says what belongs where and when: birds, frogs, insects and mammals, about 15,000 species, live,
with no server and no network. Every ID is logged with time and place; "I saw it" marks the ones you verified.

[App Store](https://apps.apple.com/app/id6837884086) · [ducktyping.dev/hark](https://ducktyping.dev/hark/) ·
code MIT ([LICENSE](LICENSE)), bundled models and data under their own licenses ([NOTICE.md](NOTICE.md)) ·
open items in [docs/RAID.md](docs/RAID.md)

## Building it yourself

The models are not in the repo (they're hundreds of MB). Make them first, into `Models/` (git-ignored):
- `Models/Perch.mlpackage`: [tools/models/perch](tools/models/perch/README.md), the Perch → Core ML pipeline,
  including the three fp16 fixes the Neural Engine needs.
- `Models/BirdNET3.mlpackage`: `tools/convert_birdnet3.py` (BirdNET's own model-converter, then a parity check).
- `Models/Geo.mlpackage`: `tools/convert_geomodel.py`.

Then `xcodegen generate` and build (below). Signing uses the author's team and the `group.dev.ducktyping.hark` App
Group: change both in `project.yml` for your own. No audio ships here either: the parity test and the on-device
self-test skip until you make fixtures from your own recordings (`tools/models/perch/make_fixtures.py`).

## Layout
- `HarkCore/`: Swift package, testable on the Mac (`cd HarkCore && swift test`). RingBuffer, Scoring (softmax,
  optional rest logit for regional slices), LabelTable, PerchClassifier (Core ML), DetectionTracker (occurrences with 60 s gaps).
  `GoldenParityTests` runs the real model on 12 windows of your audio and requires TF-reference top-1 on ANE and GPU
  (skips without fixtures or the model).
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
- `Models/`: git-ignored Core ML models (see "Building it yourself"). `tools/models/perch/`: the Perch conversion.
- `tools/gbif_ranges.py`: location filter data. Per Perch species, GBIF backbone match + global density map
  (1.40625-degree cells, >= 2 records, solid cells also mark their neighbors) -> `Hark/Resources/ranges.bin`.
  `fetch` takes ~70 min (cached/resumable in tools/data/gbif/), `build` is instant. Credit GBIF.org in the app.
- `tools/make_labels.py`: label table from Perch labels + OpenFauna names/classes (data from birdnet-go's
  vendored OpenFauna snapshot, in tools/data/). OpenFauna is CC BY-SA 4.0, so labels.json is too (see NOTICE.md).

## Models

Perch 2.0 (Models/Perch.mlpackage) and BirdNET+ V3.0 (Models/BirdNET3.mlpackage, tools/convert_birdnet3.py) in
Perch / BirdNET+ / Both modes. labels.json = Perch's 14,795 labels + 540 BirdNET+-only species
(tools/make_birdnet3_map.py, then re-run convert_geomodel.py). BirdNET+ scores map onto Perch's scale (0.75 -> 0.30);
Both = agree (P >= .83t, B >= .47t) or sure (P >= 2.33t, B >= 1.37t), from tools/bakeoff. On an iPhone 15 Pro Max ANE:
Perch 8.9 ms, BirdNET+ 8.0 ms per window.

## Location + season

`LocalContext` (HarkCore) combines, most trusted first: eBird reports within 25 km / 30 days (user's own API key,
Keychain), your patch (confirmed, or logged on 3+ days, within 10 km), the BirdNET+ Geomodel V3.0.4 (Apache 2.0;
lat/lon/week -> 14,082 species; 12,258 Perch labels mapped; all 48 weeks run so "out of season" differs from
"never here"), then the GBIF range map. Rebuild the geomodel + map: `tools/models/perch/.venv/bin/python
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
