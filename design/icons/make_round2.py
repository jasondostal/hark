"""Round 2: chirp / H / bird-of-bars hybrids."""
import math, subprocess
S = 1024

def taper(p0, c1, c2, p3, w0, w1=4, n=40):
    """Filled, tapered stroke along a cubic Bezier (wide at p0, thin at p3): a spectrogram 'note'."""
    def bez(t):
        u = 1 - t
        return tuple(u**3*a + 3*u*u*t*b + 3*u*t*t*c + t**3*d for a, b, c, d in zip(p0, c1, c2, p3))
    pts = [bez(i / n) for i in range(n + 1)]
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        x2, y2 = pts[min(i + 1, n)]; x1, y1 = pts[max(i - 1, 0)]
        dx, dy = x2 - x1, y2 - y1; L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        t = i / n; w = (w0 * (1 - t) ** 0.8 + w1) / 2
        left.append((x + nx * w, y + ny * w)); right.append((x - nx * w, y - ny * w))
    ring = left + right[::-1]
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in ring) + " Z"

NIGHT = '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#150d36"/><stop offset="1" stop-color="#04030b"/></linearGradient>'
AUR = '<linearGradient id="au" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e6ffe9"/><stop offset=".45" stop-color="#4fe6a0"/><stop offset="1" stop-color="#7a35c4"/></linearGradient>'
AURH = '<linearGradient id="auh" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7a35c4"/><stop offset=".5" stop-color="#3fd39a"/><stop offset="1" stop-color="#e6ffe9"/></linearGradient>'
GLOW = '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="16" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
BIRD = """<ellipse cx="470" cy="560" rx="235" ry="165" transform="rotate(-14 470 560)"/>
  <circle cx="660" cy="425" r="112"/><polygon points="755,402 860,438 752,468"/>
  <polygon points="300,545 105,640 135,705 330,640"/>"""

def notes(spec):   # spec: (x, top, height, slant, width)
    out = []
    for x, top, h, sl, w in spec:
        out.append(taper((x, top), (x + sl * 0.2, top + h * 0.35), (x - sl * 0.6, top + h * 0.7), (x - sl, top + h), w))
    return out

def bars(x0, x1, cy, heights, w, gap):
    out, x = [], x0
    for h in heights:
        out.append(f'<rect x="{x}" y="{cy - h/2}" width="{w}" height="{h}" rx="{w/2}"/>'); x += w + gap
    return "".join(out)

concepts = {}
# A. chirp v2: a cardinal-like phrase of downslurs, getting quicker
ch = notes([(250, 250, 470, 70, 78), (430, 300, 400, 60, 70), (590, 350, 330, 50, 62), (725, 395, 270, 40, 54), (835, 430, 220, 32, 46)])
concepts["chirp2"] = ("Chirp v2", f'<defs>{NIGHT}{AUR}{GLOW}</defs><rect width="{S}" height="{S}" fill="url(#bg)"/>'
                      f'<g fill="url(#au)" filter="url(#glow)">{"".join(f"<path d=\"{d}\"/>" for d in ch)}</g>')
# B. H of chirps: two tall downslur strokes + a short trill crossbar
hl = taper((330, 220), (350, 420), (320, 620), (300, 820), 120, 10)
hr = taper((720, 220), (740, 420), (710, 620), (690, 820), 120, 10)
trill = bars(410, 620, 520, [70, 120, 170, 120, 70], 28, 18)
concepts["hchirp"] = ("H of chirps", f'<defs>{NIGHT}{AUR}{GLOW}</defs><rect width="{S}" height="{S}" fill="url(#bg)"/>'
                      f'<g fill="url(#au)" filter="url(#glow)"><path d="{hl}"/><path d="{hr}"/>{trill}</g>')
# C. H with spectrogram crossbar, on green
cross = bars(398, 626, 512, [90, 150, 230, 300, 230, 150, 90], 22, 12)
concepts["hspec"] = ("H, spectrogram bar", f'<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#23b77a"/><stop offset="1" stop-color="#0b5d55"/></linearGradient></defs>'
                    f'<rect width="{S}" height="{S}" fill="url(#bg)"/><g fill="#fff"><rect x="245" y="240" width="135" height="544" rx="40"/><rect x="644" y="240" width="135" height="544" rx="40"/>{cross}</g>')
# D. same, night + aurora glow
concepts["hspecnight"] = ("H, night", f'<defs>{NIGHT}{AUR}{GLOW}</defs><rect width="{S}" height="{S}" fill="url(#bg)"/>'
                         f'<g fill="url(#au)" filter="url(#glow)"><rect x="245" y="240" width="135" height="544" rx="40"/><rect x="644" y="240" width="135" height="544" rx="40"/>{cross}</g>')
# E. bird of bars at night: glowing aurora bars clipped to the bird, heights varied like a spectrogram
import random; random.seed(4)
birdbars = "".join(f'<rect x="{x}" y="{200 + random.randint(0, 60)}" width="26" height="{620 - random.randint(0, 80)}" rx="13"/>' for x in range(96, 900, 40))
concepts["birdnight"] = ("Bird of bars, night", f'<defs>{NIGHT}{AUR}{GLOW}<clipPath id="bird">{BIRD}</clipPath></defs>'
                        f'<rect width="{S}" height="{S}" fill="url(#bg)"/><g filter="url(#glow)"><g clip-path="url(#bird)" fill="url(#au)">{birdbars}</g></g>'
                        f'<circle cx="690" cy="405" r="16" fill="#150d36"/>')
# F. bird singing chirps
sing = notes([(720, 250, 200, 30, 50), (820, 300, 170, 26, 44), (905, 345, 140, 22, 38)])
concepts["birdsing"] = ("Bird + chirps", f'<defs>{NIGHT}{AUR}{GLOW}</defs><rect width="{S}" height="{S}" fill="url(#bg)"/>'
                       f'<g fill="#e9fff0" transform="translate(-60 60) scale(.8) translate(60 160)">{BIRD}</g><circle cx="530" cy="560" r="13" fill="#150d36"/>'
                       f'<g fill="url(#au)" filter="url(#glow)">{"".join(f"<path d=\"{d}\"/>" for d in sing)}</g>')

for key, (title, body) in concepts.items():
    open(f"{key}.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">{body}</svg>')
    subprocess.run(["rsvg-convert", "-w", str(S), "-h", str(S), f"{key}.svg", "-o", f"{key}.png"], check=True)
open("round2.txt", "w").write("\n".join(f"{k}\t{t}" for k, (t, _) in concepts.items()))
print("ok")
