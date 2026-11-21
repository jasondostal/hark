# Hark (working name)

Free, noncommercial iPhone app: pull it out, hear something, find out what it is. Runs Google's Perch 2.0 on-device
(Neural Engine) for birds, frogs, insects and mammals (14,795 classes). Every ID is logged with time and place;
"I saw it" marks the ones you verified.

## Layout
- `HarkCore/`: Swift package, testable on the Mac (`cd HarkCore && swift test`). RingBuffer, Scoring (softmax,
  optional rest logit for regional slices), LabelTable, PerchClassifier (Core ML), DetectionTracker (occurrences with 60 s gaps).
  `GoldenParityTests` runs the real model on 12 backyard windows and requires TF-reference top-1 on ANE and GPU.
- `Hark/`: SwiftUI app. AudioCapture (AVAudioEngine, .measurement mode, -> 32 kHz mono), Listener (scores the newest
  5 s once a second, logs to SwiftData), "maybe" tier (species between half the
  threshold and the threshold in the last 15 s, loggable by hand), live FFT spectrogram (independent of Perch), Log tab.
- `Models/Perch.mlpackage`: git-ignored. Build it with ~/working/perch-spike (`./build.sh`), then
  `cp -R ../perch-spike/models/perch_v2_full_fp16.mlpackage Models/Perch.mlpackage`.
- `tools/make_labels.py`: label table from Perch labels + OpenFauna names/classes (data copied from birdnet-go's
  vendored snapshot on CORTEX into tools/data/). OpenFauna's license still needs checking before any public release.

## Build / install (headless)
```
xcodegen generate
xcodebuild -project Hark.xcodeproj -scheme Hark -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> DerivedData/Build/Products/Release-iphoneos/Hark.app
xcrun devicectl device process launch --console --device <udid> dev.ducktyping.hark -selftest   # ANE parity + timing
```
Launch args: `-selftest` (golden windows on ANE/GPU/CPU, prints HARK-SELFTEST lines), `-autolisten` (start listening on launch).
