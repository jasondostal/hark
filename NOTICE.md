# Third-party components

Hark's own code is MIT ([LICENSE](LICENSE)). These pieces are someone else's work, under their own licenses. The app
lists the same credits in Settings > About > Acknowledgements.

## Models (not in this repo; built into `Models/` by the scripts in `tools/`)

| Component | Use | License |
|---|---|---|
| [Perch 2.0](https://www.kaggle.com/models/google/bird-vocalization-classifier), Google DeepMind | Sound ID model | Apache 2.0 |
| [BirdNET+ 3.0](https://github.com/birdnet-team/model-converter), K. Lisa Yang Center for Conservation Bioacoustics (Cornell Lab of Ornithology) and Chemnitz University of Technology | Second sound ID model | Apache 2.0 |
| [BirdNET+ Geomodel 3.0.4](https://github.com/birdnet-team/geomodel), same authors | Species by place and week | Apache 2.0 |

`Hark/Resources/LICENSE-Apache-2.0.txt` ships in the app for these. `Hark/Resources/birdnet3_labels.json` comes
from the BirdNET+ model's label file (Apache 2.0); `geo_map.bin` and `birdnet3_map.bin` are index maps derived from
the BirdNET+ labels.

## Data in this repo

| File | Source | License |
|---|---|---|
| `Hark/Resources/labels.json`, `tools/labels.json`, `HarkCore/Tests/HarkCoreTests/Fixtures/labels.json` | Adapted from [OpenFauna](https://github.com/tphakala/openfauna) (names, groups, iNaturalist ids), with Perch's label list, groups and emoji added | **CC BY-SA 4.0**: these files stay CC BY-SA, not MIT |
| `Hark/Resources/ranges.bin` | A presence grid (1.40625° cells) derived from [GBIF.org](https://www.gbif.org) occurrence maps via the GBIF maps API (`tools/gbif_ranges.py`) | Built from datasets published under CC0, CC BY or CC BY-NC, per dataset. Credit GBIF.org. Hark is free and noncommercial; check GBIF's terms before any commercial use. |

eBird data is fetched at run time only with the user's own API key, under the [eBird API Terms of Use](https://www.birds.cornell.edu/home/ebird-api-terms-of-use/); none is stored here.

## Icons and fonts

| Component | Use | License |
|---|---|---|
| [Font Awesome Free 6.5.2](https://fontawesome.com/license/free) | Frog, locust and spider symbols (`tools/symbols`, the app's symbol set) | CC BY 4.0 |
| [Silkscreen](https://fonts.google.com/specimen/Silkscreen), Jason Kottke | 8-bit look | SIL OFL 1.1 (`Hark/Resources/Fonts/OFL-Silkscreen.txt`) |
| [Saira Stencil One](https://fonts.google.com/specimen/Saira+Stencil+One), Omnibus-Type | Duck Blind look | SIL OFL 1.1 (`Hark/Resources/Fonts/OFL-SairaStencilOne.txt`) |

## Audio

None. The parity tests and the on-device self-test use your own recordings (`tools/models/perch/README.md`).
