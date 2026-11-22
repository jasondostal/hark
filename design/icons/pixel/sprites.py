# The pixel critters alone (no backdrop or sound arcs) for the 8-bit look's row icons and spectrogram pins.
# Each is cropped, centred on a square and written 1x into the app's asset catalog as px-<name>.
#   uv run -q --with pillow design/icons/pixel/sprites.py
import os, json
from PIL import Image
import gen
OUT = os.path.join(gen.HERE, "..", "..", "..", "Hark", "Shared", "Assets.xcassets")
for name, rows, pal in [("bird", gen.BIRD, gen.BIRD_PAL), ("toad", gen.TOAD, gen.TOAD_PAL), ("cricket", gen.CRICKET, gen.CRICKET_PAL),
                        ("chipmunk", gen.CHIPMUNK, gen.CHIP_PAL), ("owl", gen.OWL, gen.OWL_PAL)]:
    w = max(len(r) for r in rows); h = len(rows); n = max(w, h) + 2
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ox, oy = (n - w) // 2, (n - h) // 2
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != "." and ch in pal: img.putpixel((ox + x, oy + y), gen.hx(pal[ch]))
    d = os.path.join(OUT, f"px-{name}.imageset"); os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, f"px-{name}.png"))
    json.dump({"images": [{"filename": f"px-{name}.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1},
               "properties": {"preserves-vector-representation": False, "template-rendering-intent": "original"}},
              open(os.path.join(d, "Contents.json"), "w"), indent=2)
    print(name, n)
