# Pixel critter alternate icons for Hark: 32x32 art, each critter calling, with the main icon's
# green-to-purple sound arcs coming off it. Renders previews + a contact sheet.
#   uv run --with pillow design/icons/pixel/gen.py
import os, math
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
N = 32
def hx(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) + (255,)

def backdrop():
    img = [[None]*N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            d = math.hypot(x - 16, y - 15) / 22
            a = max(0, 1 - d)
            base = (14, 9, 36); glow = (40, 26, 84)
            c = tuple(int(base[i] + (glow[i]-base[i]) * a * a) for i in range(3))
            img[y][x] = c + (255,)
    return img

WAVE = ["#d8fbe6", "#a8f2c8", "#5fe0a0", "#3fcf8e", "#4aa7a0", "#5a7fb0", "#7050c0", "#8a3fd0"]
def arc(img, cx, cy, r, h):
    # a ")" arc of radius r centred at (cx, cy), h rows tall, coloured top->bottom like the main icon
    for k, y in enumerate(range(cy - h//2, cy + h//2 + 1)):
        dy = y - cy
        if abs(dy) > r: continue
        x = cx + int(round(math.sqrt(r*r - dy*dy)))
        c = hx(WAVE[min(len(WAVE)-1, k * len(WAVE) // (h+1))])
        for xx in (x, x+1):
            if 0 <= xx < N and 0 <= y < N: img[y][xx] = c

def waves(img, cx, cy, rs=(4, 7, 10), hs=(7, 11, 15)):
    for r, h in zip(rs, hs): arc(img, cx, cy, r, h)

def blit(img, rows, pal, ox, oy):
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != "." and ch in pal:
                xx, yy = ox + x, oy + y
                if 0 <= xx < N and 0 <= yy < N: img[yy][xx] = hx(pal[ch])

def save(img, name):
    im = Image.new("RGBA", (N, N))
    im.putdata([c for row in img for c in row])
    big = im.resize((1024, 1024), Image.NEAREST)
    big.convert("RGB").save(os.path.join(HERE, f"{name}.png"))
    return big

# ── critters ────────────────────────────────────────────────────────────────
CHIPMUNK = [  # facing right, sitting up, mouth open (the "chip!")
    "...........dd.....",
    "..........dlld....",
    ".dd......dooood...",
    "dood....doooooodd.",
    "dood...dooookooodd",
    "doood..dddddwoooodk",
    ".dood..dwwwwwooood.",
    ".dood..doooooowpp..",
    "..dood..doooowwp...",
    "..dood..dooowwww...",
    "...dooddooddwwwd...",
    "...doooooodwwwwd...",
    "....dooooodwwwlld..",
    "....doooodwwwwwd...",
    ".....doooodwwwwd...",
    ".....dooooowwwwd...",
    "......dooooowwd....",
    "......dddolldlld...",
    ".......ddddddddd...",
]
CHIP_PAL = {"d": "#3e220f", "o": "#c47a36", "l": "#e8b26e", "w": "#f5e6c8", "k": "#0e0a0c", "p": "#e45d7c"}

BIRD = [  # a singing songbird (cardinal-ish red), facing right, beak open
    "........rr........",
    ".......rrrr.......",
    "......rrrrrr......",
    ".....rrrrrrrr.....",
    ".....rrkkrkrry....",
    "....rrrkkkrrryy...",
    "....rrrrkkrrr.....",
    "...rrrrrrrrrryy...",
    "..rrrrrrrrrrr.y...",
    ".rrrrrrrrrrrr.....",
    ".rrRRRrrrrrrr.....",
    "rrRRRRRrrrrr......",
    "rRRRRRRRrrrr......",
    "RRRRRRRRrrr.......",
    "RRRRRRRrrr........",
    "RRRR..rrr.........",
    "RR.....bb.........",
    "......b..b........",
]
BIRD_PAL = {"r": "#e2323a", "R": "#9c1c2a", "k": "#120a0e", "y": "#f4a23a", "b": "#6a4a3a"}

TOAD = [  # American toad, vocal sac blown up, facing right
    "......gggg........",
    ".....gGggGgg......",
    "....ggkwgggggg....",
    "...ggkkgggggggg...",
    "..ggggggggggggg...",
    ".gGgggGggggggg....",
    "gggggggggggwwwww..",
    "gGgggggGggwwwwwww.",
    "ggggGgggggwwwwwwww",
    "gggggggggggwwwwwww",
    "ggGgggggGgggwwwww.",
    ".gggggggggggg.....",
    "..yggg.....gggy...",
    ".yy.yy....yy.yy...",
]
TOAD_PAL = {"g": "#7a8a3a", "G": "#4e5a22", "k": "#120e0a", "w": "#ece2c4", "y": "#a6a050"}

CRICKET = [  # field cricket, side view, wings raised (that's how they sing)
    "a.................",
    ".a................",
    "..a.......wwww....",
    "...a....wwwwwwww..",
    "....a..wwWwwwWwww.",
    "....kkwwWwwwwWwwww",
    "...kkkkwwwwwwwwwww",
    "..kkekkkwwwwwwwww.",
    "..kkkkkkkkkkkkkk..",
    "..kkkkkkkkkkkkkkkk",
    "...kkkkkkkkkkkkk.c",
    "....l.l...l.l.ll..",
    "...l..l...l..l..l.",
    "..l...l....l..l..l",
]
CRICKET_PAL = {"k": "#5a3a24", "e": "#f0d878", "w": "#b8915c", "W": "#7a5634", "a": "#8a6a4c", "l": "#6a4a30", "c": "#5a3a24"}

OWL = [  # barred owl, head-on, hooting
    "....bbbbbbbb....",
    "...bbwbbbbwbb...",
    "..bbwwbbbbwwbb..",
    ".bbwkkwbbwkkwbb.",
    ".bbwkkwbbwkkwbb.",
    ".bbbwwbyybwwbbb.",
    ".bbbbbbyybbbbbb.",
    ".bbwbwbbbbwbwbb.",
    ".bwbwbwbbwbwbwb.",
    ".bbwbwbwbwbwbbb.",
    "..bwbwbwbwbwbb..",
    "..bbwbwbwbwbbb..",
    "...bbbbbbbbbb...",
    "....yy....yy....",
]
OWL_PAL = {"b": "#7a6650", "w": "#e8dcc4", "k": "#100c0a", "y": "#e8c040"}

def make(name, sprite, pal, ox, oy, wx, wy, **kw):
    img = backdrop(); waves(img, wx, wy, **kw); blit(img, sprite, pal, ox, oy); return save(img, name)

icons = [
    make("chipmunk", CHIPMUNK, CHIP_PAL, 2, 7, 18, 14),
    make("bird", BIRD, BIRD_PAL, 2, 8, 18, 13),
    make("toad", TOAD, TOAD_PAL, 1, 10, 19, 17),
    make("cricket", CRICKET, CRICKET_PAL, 1, 9, 19, 15),
    make("owl", OWL, OWL_PAL, 3, 9, 19, 14),
]
# contact sheet, with the iOS squircle mask approximated by rounded corners
sheet = Image.new("RGB", (5 * 300 + 60, 360), (245, 245, 247))
for i, im in enumerate(icons):
    s = im.resize((260, 260), Image.NEAREST)
    m = Image.new("L", (260, 260), 0)
    from PIL import ImageDraw
    ImageDraw.Draw(m).rounded_rectangle((0, 0, 259, 259), radius=58, fill=255)
    sheet.paste(s, (40 + i * 300, 50), m)
sheet.save(os.path.join(HERE, "sheet.png"))
print("ok")
