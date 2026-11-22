"""Font Awesome Free 6.5.2 solid icons (CC BY 4.0, credited in Settings > Acknowledgements) -> SF Symbol templates,
for the animals SF Symbols lacks. Each becomes <name>.fill in Hark/Shared/Assets.xcassets, so it scales and tints
like a system symbol (Image(symbol:) in Symbols.swift).

  python3 make_symbols.py          # reads tools/symbols/*.svg
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "Hark", "Shared", "Assets.xcassets")
SCALE = 0.19          # 512-unit-tall icon -> ~97 units, about bird.fill's size against the Regular-M cap height
L, BASE, CAP = 1391.51, 1126.0, 70.46   # Regular-M left margin, baseline, cap height in the template

for name in ("frog", "locust", "spider"):
    svg = open(os.path.join(HERE, "symbols", f"{name}.svg")).read()
    w, h = (float(v) for v in re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg).groups())
    d = re.search(r' d="([^"]+)"', svg).group(1)
    top = BASE - CAP / 2 - h * SCALE / 2
    right = L + w * SCALE
    out = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<!-- {name} from Font Awesome Free 6.5.2 (CC BY 4.0, https://fontawesome.com/license/free) -->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200">
 <g id="Notes"><text x="263" y="292">{name}.fill</text></g>
 <g id="Guides">
  <line id="Baseline-S" x1="263" x2="3036" y1="696" y2="696" stroke="black" stroke-width="0.5"/>
  <line id="Capline-S" x1="263" x2="3036" y1="625.541" y2="625.541" stroke="black" stroke-width="0.5"/>
  <line id="Baseline-M" x1="263" x2="3036" y1="1126" y2="1126" stroke="black" stroke-width="0.5"/>
  <line id="Capline-M" x1="263" x2="3036" y1="1055.54" y2="1055.54" stroke="black" stroke-width="0.5"/>
  <line id="Baseline-L" x1="263" x2="3036" y1="1556" y2="1556" stroke="black" stroke-width="0.5"/>
  <line id="Capline-L" x1="263" x2="3036" y1="1485.54" y2="1485.54" stroke="black" stroke-width="0.5"/>
  <line id="left-margin-Regular-M" x1="{L}" x2="{L}" y1="1030.79" y2="1150.12" stroke="black" stroke-width="0.5"/>
  <line id="right-margin-Regular-M" x1="{right:.2f}" x2="{right:.2f}" y1="1030.79" y2="1150.12" stroke="black" stroke-width="0.5"/>
 </g>
 <g id="Symbols">
  <g id="Regular-M" transform="matrix({SCALE} 0 0 {SCALE} {L} {top:.2f})">
   <path d="{d}"/>
  </g>
 </g>
</svg>
'''
    dst = os.path.join(ASSETS, f"{name}.fill.symbolset")
    os.makedirs(dst, exist_ok=True)
    open(os.path.join(dst, f"{name}.fill.svg"), "w").write(out)
    json.dump({"info": {"author": "xcode", "version": 1}, "symbols": [{"filename": f"{name}.fill.svg", "idiom": "universal"}]},
              open(os.path.join(dst, "Contents.json"), "w"), indent=2)
    print(f"{name}.fill  {w:.0f}x{h:.0f}")
