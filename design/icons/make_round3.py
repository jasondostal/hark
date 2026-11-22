"""Round 3: variations on the original Chirp (constant-width glowing strokes on night)."""
import subprocess, random
S = 1024
DEFS = '''<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#140c33"/><stop offset="1" stop-color="#05040d"/></linearGradient>
<linearGradient id="st" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d9ffe0"/><stop offset=".45" stop-color="#46e39a"/><stop offset="1" stop-color="#6b2fb3"/></linearGradient>
<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="18" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="haze" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="70"/></filter>'''
BG = f'<rect width="{S}" height="{S}" fill="url(#bg)"/>'

def stroke(x, top, h, bend=30, lean=50):
    """A chirp: a gentle downslur from (x, top), h tall, bowing right then drifting left."""
    return f'M{x} {top} C {x+bend} {top+h*0.3}, {x+bend*0.4} {top+h*0.65}, {x-lean} {top+h}'

def chirps(paths, width=52, opacity=1):
    return f'<g fill="none" stroke="url(#st)" stroke-width="{width}" stroke-linecap="round" filter="url(#glow)" opacity="{opacity}">' + "".join(f'<path d="{p}"/>' for p in paths) + "</g>"

ORIG = ["M300 270 C 330 420, 300 560, 250 760", "M520 230 C 560 420, 530 600, 470 800", "M740 300 C 770 430, 745 560, 700 720"]
random.seed(7)
stars = "".join(f'<circle cx="{random.randint(60,964)}" cy="{random.randint(60,420)}" r="{random.choice([2.5,3.5,5])}" fill="#fff" opacity="{random.choice([.35,.55,.8])}"/>' for _ in range(26))

concepts = {
 "c_orig": ("Original", BG + chirps(ORIG)),
 "c_rise": ("Rising phrase", BG + chirps([stroke(270, 470, 300), stroke(470, 360, 410), stroke(680, 230, 540)], 54)),
 "c_harm": ("Harmonics", BG + chirps([stroke(285, 420, 380), stroke(505, 380, 420), stroke(725, 440, 340)], 50)
                         + chirps([stroke(300, 230, 150, 14, 22), stroke(520, 190, 160, 14, 22), stroke(740, 260, 130, 14, 22)], 26, .55)),
 "c_stars": ("Night sky", BG + stars + chirps([stroke(300, 330, 420), stroke(520, 290, 480), stroke(740, 350, 380)], 52)),
 "c_four": ("Four-note phrase", BG + chirps([stroke(230, 300, 420, 26, 40), stroke(410, 330, 380, 24, 36), stroke(590, 360, 340, 22, 32), stroke(770, 390, 300, 20, 28)], 46)),
 "c_full": ("Fuller strokes", BG + '<ellipse cx="512" cy="540" rx="330" ry="260" fill="#3b2a8a" opacity=".55" filter="url(#haze)"/>'
                        + chirps([stroke(310, 290, 450, 36, 56), stroke(520, 250, 510, 36, 56), stroke(730, 310, 420, 36, 56)], 70)),
}
for key, (title, body) in concepts.items():
    open(f"{key}.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}"><defs>{DEFS}</defs>{body}</svg>')
    subprocess.run(["rsvg-convert", "-w", str(S), "-h", str(S), f"{key}.svg", "-o", f"{key}.png"], check=True)
open("round3.txt", "w").write("\n".join(f"{k}\t{t}" for k, (t, _) in concepts.items()))
