"""Hark app-icon concepts: SVG sources -> 1024 px PNGs (rsvg-convert) -> a comparison sheet."""
import subprocess, os
S = 1024
BIRD = """
  <ellipse cx="470" cy="560" rx="235" ry="165" transform="rotate(-14 470 560)"/>
  <circle cx="660" cy="425" r="112"/>
  <polygon points="755,402 860,438 752,468"/>
  <polygon points="300,545 105,640 135,705 330,640"/>"""

concepts = {
"chirp": ("Chirp", f"""
<defs>
 <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#140c33"/><stop offset="1" stop-color="#05040d"/></linearGradient>
 <linearGradient id="st" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d9ffe0"/><stop offset=".45" stop-color="#46e39a"/><stop offset="1" stop-color="#6b2fb3"/></linearGradient>
 <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="18" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>
<rect width="{S}" height="{S}" fill="url(#bg)"/>
<g fill="none" stroke="url(#st)" stroke-width="52" stroke-linecap="round" filter="url(#glow)">
 <path d="M300 270 C 330 420, 300 560, 250 760"/>
 <path d="M520 230 C 560 420, 530 600, 470 800"/>
 <path d="M740 300 C 770 430, 745 560, 700 720"/>
</g>"""),
"stripes": ("Bird of bars", f"""
<defs>
 <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2a1260"/><stop offset=".55" stop-color="#0f6b6b"/><stop offset="1" stop-color="#4fd18b"/></linearGradient>
 <clipPath id="bird">{BIRD}</clipPath>
</defs>
<rect width="{S}" height="{S}" fill="url(#bg)"/>
<g clip-path="url(#bird)" fill="#ffffff">
 {''.join(f'<rect x="{x}" y="0" width="26" height="{S}" rx="13" opacity="{0.95 if (x//40)%2 else 0.8}"/>' for x in range(96, 900, 40))}
</g>
<circle cx="690" cy="405" r="16" fill="#1b2f5a"/>"""),
"owl": ("Owl rings", f"""
<defs><radialGradient id="bg" cx=".5" cy=".4" r=".8"><stop offset="0" stop-color="#1d4a4f"/><stop offset="1" stop-color="#081a1d"/></radialGradient></defs>
<rect width="{S}" height="{S}" fill="url(#bg)"/>
<polygon points="215,250 345,370 255,420" fill="#e8a33d"/><polygon points="809,250 679,370 769,420" fill="#e8a33d"/>
{''.join(f'<circle cx="{cx}" cy="530" r="{r}" fill="none" stroke="{c}" stroke-width="30"/>' for cx in (365,659) for r,c in ((165,"#e8a33d"),(118,"#f6d27a"),(72,"#e8a33d")))}
<circle cx="365" cy="530" r="36" fill="#0b0b0b"/><circle cx="659" cy="530" r="36" fill="#0b0b0b"/>
<circle cx="378" cy="517" r="11" fill="#fff"/><circle cx="672" cy="517" r="11" fill="#fff"/>
<polygon points="512,640 478,705 546,705" fill="#f08a3c"/>"""),
"perch": ("Perched on a wave", f"""
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffb35c"/><stop offset=".55" stop-color="#ff6b7d"/><stop offset="1" stop-color="#5b3a8c"/></linearGradient></defs>
<rect width="{S}" height="{S}" fill="url(#bg)"/>
<circle cx="760" cy="300" r="110" fill="#ffe3a3" opacity=".85"/>
<g fill="#241433" transform="translate(40 -60) scale(.82) translate(110 120)">{BIRD}
 <rect x="430" y="700" width="18" height="90" rx="9"/><rect x="510" y="690" width="18" height="100" rx="9"/></g>
<polyline points="60,770 150,770 190,700 230,840 270,730 310,800 350,770 640,770 680,690 720,850 760,720 800,800 840,770 964,770"
  fill="none" stroke="#241433" stroke-width="26" stroke-linejoin="round" stroke-linecap="round"/>"""),
"hwave": ("H wave", f"""
<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#23b77a"/><stop offset="1" stop-color="#0b5d55"/></linearGradient></defs>
<rect width="{S}" height="{S}" fill="url(#bg)"/>
<rect x="245" y="240" width="135" height="544" rx="40" fill="#fff"/><rect x="644" y="240" width="135" height="544" rx="40" fill="#fff"/>
<polyline points="380,512 420,512 450,420 490,610 530,380 570,640 600,470 625,512 644,512" fill="none" stroke="#fff" stroke-width="40" stroke-linejoin="round" stroke-linecap="round"/>"""),
"leaf": ("Leaf, listening", f"""
<rect width="{S}" height="{S}" fill="#f3eddc"/>
<path d="M230 800 C 200 520, 380 300, 640 270 C 660 520, 500 760, 230 800 Z" fill="#3f8f52"/>
<path d="M240 790 C 360 640, 470 480, 620 290" fill="none" stroke="#bfe3b3" stroke-width="16" stroke-linecap="round"/>
{''.join(f'<path d="M{620+d*0.2} {330-d*0.9} A {d} {d} 0 0 1 {700+d*0.95} {420-d*0.15}" fill="none" stroke="#2f6f8f" stroke-width="34" stroke-linecap="round" opacity="{o}"/>' for d,o in ((90,1),(170,.75),(250,.5)))}"""),
}

for key, (title, body) in concepts.items():
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">{body}</svg>'
    open(f"{key}.svg", "w").write(svg)
    subprocess.run(["rsvg-convert", "-w", str(S), "-h", str(S), f"{key}.svg", "-o", f"{key}.png"], check=True)
print("rendered", len(concepts))
