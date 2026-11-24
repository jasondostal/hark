# Hark RAID log

Risks, Assumptions, Issues, Dependencies. Newest first within each section. Close an item by striking it through
with the date and where it landed, so the history stays.

## Issues

| ID | Opened | Issue | Status / fix |
|---|---|---|---|
| I-3 | 2026-11-24 | App 1.0 bundles `selftest.f32`: three 5 s windows of backyard audio, used only by the `-selftest` launch argument. | Removed from the repo and from `Hark/Resources` 2026-11-24 (now git-ignored, made from your own audio by `tools/models/perch/make_fixtures.py`). **Ships with the next App Store update**: build from a tree without `Hark/Resources/selftest.*`. |
| I-2 | 2026-11-24 | OFL fonts (Silkscreen, Saira Stencil One) shipped in 1.0 without the OFL license text, which OFL 1.1 requires alongside the font files. The in-app Acknowledgements credit them but don't include the text. | Fixed in repo 2026-11-24: `Hark/Resources/Fonts/OFL-*.txt`, bundled with the app. **Ships with the next App Store update.** |
| I-1 | 2026-11-23 | Perch's "Siren" class (the salamander genus) was grouped as an amphibian, so a police siren could log as one. | Fixed 88c03f9, not in 1.0 (build 3). **Ships with the next update.** Then add the siren clip back to ducktyping.dev/hark/#test-sounds. |

## Risks

| ID | Risk | Mitigation |
|---|---|---|
| R-4 | 1.1 settings that change what the models hear (gain, high-pass up to 1 kHz, check interval, voices guard, body sounds) were checked in the simulator and on the golden windows, not against the bake-off. Defaults are exactly 1.0's behavior. | Leave defaults alone. Bake-off any change of default first. Measured: Perch scores hold from -10 to +20 dB on the golden windows and collapse below about -20 dB (peaks under 0.002). |
| R-3 | `ranges.bin` is derived from GBIF data that includes CC BY-NC datasets. | Hark stays free and noncommercial. Any paid version, tip jar or ads needs a license review of the range data first. |
| R-2 | `labels.json` is CC BY-SA 4.0 (adapted from OpenFauna) inside an MIT repo. | NOTICE.md marks those files as CC BY-SA. Keep the attribution in the app. |
| R-1 | The app is about 390 MB (two full models). Cellular download limits and storage complaints. | Regional Perch slices (35 MB) are an option if reviews complain. |

## Assumptions

| ID | Assumption |
|---|---|
| A-2 | Users bring their own eBird API key. Hark never ships or proxies one. |
| A-1 | Hark is free, has no account, collects no data, and has no server. The privacy page and App Privacy label ("Data Not Collected") depend on it: update them first if that ever changes. |

## Dependencies

| ID | Dependency | Notes |
|---|---|---|
| D-5 | ducktyping.dev/hark/ and /hark/privacy/ | App Store Connect links to both. They must never vanish in a site deploy. |
| D-4 | eBird API | Optional, user's key, 25 km / 30 days. |
| D-3 | GBIF maps API | Build time only (`tools/gbif_ranges.py`, ~70 min fetch). No account needed. |
| D-2 | BirdNET+ 3.0 + Geomodel 3.0.4 (birdnet-team) | Converted with BirdNET's own model-converter. |
| D-1 | Perch 2.0 ONNX `no_dft` export (Hugging Face `tphakala/Perch-v2-Models`) and the Kaggle TF model for parity | The official Kaggle export can't be converted directly (jax2tf). See tools/models/perch. |
