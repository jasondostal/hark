#!/usr/bin/env python3
"""Build Hark's location filter from GBIF occurrence records (open data, all taxa).

For every Perch species class: match its scientific name to the GBIF backbone, then fetch GBIF's global
density map as two EPSG:4326 vector tiles binned into 1.40625-degree squares (128 x 256 cells worldwide).
Each species ends up with a {cell: record count} map. Results are cached per species in tools/data/gbif/,
so the run can be stopped and resumed.

  python tools/gbif_ranges.py fetch     # slow: ~15k matches + ~30k tiles, polite concurrency
  python tools/gbif_ranges.py build     # -> Hark/Resources/ranges.bin

ranges.bin (little-endian):
  magic 'HRNG', u16 version=1, u16 cols=256, u16 rows=128, u16 nSpecies=len(labels), u32 nCells
  then nCells x (u32 cellIndex, u32 offset, u16 count), sorted by cellIndex
  then the u16 label indices, concatenated
cellIndex = row * 256 + col, row 0 at 90S, col 0 at 180W. Classes with no GBIF match or no records never
appear in any cell; the app treats them as "unknown range" (never flagged), not as out of range.

Data credit: GBIF.org occurrence data (CC0 / CC BY / CC BY-NC records). Cite GBIF in the app.
"""
import json, os, sys, struct, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.abspath(__file__))
LABELS = os.path.join(ROOT, '..', 'Hark', 'Resources', 'labels.json')
CACHE = os.path.join(ROOT, 'data', 'gbif')
OUT = os.path.join(ROOT, '..', 'Hark', 'Resources', 'ranges.bin')
UA = {'User-Agent': 'hark-range-builder/0.1 (noncommercial species-range grid)'}
COLS, ROWS, SQUARE = 256, 128, 4          # 512 px tiles, 4 px squares -> 128 cells per 180 degrees
MIN_RECORDS = 2                           # a single record in a cell is too often an escape or a misID
NEIGHBOR_RECORDS = 25                     # cells this solid also mark their 8 neighbors (range edges)


def get(url, raw=False, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                b = r.read()
                return b if raw else json.loads(b)
        except urllib.error.HTTPError as e:
            if e.code == 404: return b'' if raw else {}
            if e.code not in (429, 500, 502, 503, 504) or i == tries - 1: raise
        except (urllib.error.URLError, TimeoutError):
            if i == tries - 1: raise
        time.sleep(2 ** i * 2)


def match(name):
    d = get('https://api.gbif.org/v1/species/match?strict=true&name=' + urllib.parse.quote(name))
    if d.get('matchType') not in ('EXACT', 'FUZZY') or d.get('rank') not in ('SPECIES', 'SUBSPECIES'):
        return None
    return d.get('acceptedUsageKey') or d.get('usageKey')


def tile_cells(key, t):
    import mapbox_vector_tile as mvt
    b = get(f'https://api.gbif.org/v2/map/occurrence/density/0/{t}/0.mvt?srs=EPSG:4326&taxonKey={key}'
            f'&bin=square&squareSize={SQUARE}', raw=True)
    if not b: return {}
    cells = {}
    for layer in mvt.decode(b).values():
        ext = layer['extent']; per = ext / (ROWS)         # tile = 128 x 128 squares
        for f in layer['features']:
            ring = f['geometry']['coordinates'][0]
            x = sum(p[0] for p in ring[:-1]) / max(len(ring) - 1, 1)
            y = sum(p[1] for p in ring[:-1]) / max(len(ring) - 1, 1)
            col = int(x // per); row = int(y // per)        # decode() flips y so row 0 = south
            if not (0 <= col < ROWS and 0 <= row < ROWS): continue
            c = row * COLS + t * ROWS + col
            cells[c] = cells.get(c, 0) + int(f['properties'].get('total', 0))
    return cells


def fetch_one(i, name):
    path = os.path.join(CACHE, f'{i}.json')
    if os.path.exists(path): return 'cached'
    key = match(name)
    cells = {}
    if key:
        for t in (0, 1):
            for c, n in tile_cells(key, t).items(): cells[c] = cells.get(c, 0) + n
    with open(path + '.tmp', 'w') as f: json.dump({'name': name, 'key': key, 'cells': cells}, f)
    os.replace(path + '.tmp', path)
    return 'nomatch' if not key else f'{len(cells)} cells'


def fetch():
    os.makedirs(CACHE, exist_ok=True)
    labels = json.load(open(LABELS))
    todo = [(i, l['s']) for i, l in enumerate(labels) if l['g'] != 'sound'
            and not os.path.exists(os.path.join(CACHE, f'{i}.json'))]
    print(f'{len(todo)} species to fetch', flush=True)
    done = 0; t0 = time.time()
    with ThreadPoolExecutor(6) as ex:
        futs = {ex.submit(fetch_one, i, s): (i, s) for i, s in todo}
        for fu in as_completed(futs):
            i, s = futs[fu]; done += 1
            try: r = fu.result()
            except Exception as e: r = f'ERROR {e}'
            if done % 200 == 0 or r.startswith('ERROR'):
                rate = done / (time.time() - t0)
                print(f'{done}/{len(todo)} {rate:.1f}/s eta {(len(todo) - done) / rate / 60:.0f} min | {s}: {r}', flush=True)
    print('fetch done', flush=True)


def build():
    labels = json.load(open(LABELS))
    by_cell = {}; matched = present = 0
    for i in range(len(labels)):
        p = os.path.join(CACHE, f'{i}.json')
        if not os.path.exists(p): continue
        d = json.load(open(p))
        if d['key']: matched += 1
        kept = set()
        for c, n in d['cells'].items():
            c = int(c); r, k = divmod(c, COLS)
            if n >= MIN_RECORDS: kept.add(c)
            if n >= NEIGHBOR_RECORDS:   # solid population: also plausible one cell (~150 km) over
                for dr in (-1, 0, 1):
                    for dk in (-1, 0, 1):
                        if 0 <= r + dr < ROWS: kept.add((r + dr) * COLS + (k + dk) % COLS)
        if kept: present += 1
        for c in kept: by_cell.setdefault(c, []).append(i)
    cells = sorted(by_cell)
    body = b''.join(struct.pack(f'<{len(by_cell[c])}H', *sorted(by_cell[c])) for c in cells)
    head = struct.pack('<4sHHHHI', b'HRNG', 1, COLS, ROWS, len(labels), len(cells))
    idx = b''; off = 0
    for c in cells:
        idx += struct.pack('<IIH', c, off, len(by_cell[c])); off += len(by_cell[c])
    with open(OUT, 'wb') as f: f.write(head + idx + body)
    species = sum(1 for l in labels if l['g'] != 'sound')
    print(f'{species} species classes, {matched} matched in GBIF, {present} with range data; '
          f'{len(cells)} cells, {off} entries, {os.path.getsize(OUT) / 1e6:.1f} MB -> {OUT}')


if __name__ == '__main__':
    {'fetch': fetch, 'build': build}[sys.argv[1]]()
