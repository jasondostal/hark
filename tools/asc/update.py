#!/usr/bin/env python3
"""update.py: start an update. Makes the App Store version if it isn't there yet and pushes What's New, the
description, keywords, promo text and the review notes from docs/store.md. Leaves app-level fields alone
(categories, age rating, subtitle): those are listing.py's, and only matter for a first release.

  tools/asc/.venv/bin/python tools/asc/update.py 1.1 [--dry]

Then: shots.py for new screenshots, attach the build, submit.py <build>."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from asc import call

APP = '6837884086'
VERSION = sys.argv[1]
DRY = '--dry' in sys.argv
md = open(os.path.join(os.path.dirname(__file__), '..', '..', 'docs', 'store.md')).read()

def section(title):
    m = re.search(r'^## ' + re.escape(title) + r'[^\n]*\n\n(.*?)(?=\n## |\Z)', md, re.S | re.M)
    return m.group(1).strip()

desc, news, notes, promo = section('Description'), section("What's New"), section('Review notes'), section('Promotional text')
keywords = re.search(r'`([^`]+)`', section('Keywords')).group(1)
for k, v, n in [('description', desc, 4000), ("what's new", news, 4000), ('review notes', notes, 4000), ('promo', promo, 170), ('keywords', keywords, 100)]:
    print(f'{k}: {len(v)}/{n}' + ('  TOO LONG' if len(v) > n else ''))
    assert len(v) <= n
if DRY: sys.exit()

def must(label, r):
    if 'httpError' in r:
        sys.exit(f'{label}: {r["httpError"]} ' + json.dumps(r['body'].get('errors', r['body']))[:900])
    print('  ok', label)
    return r

versions = call('GET', f'/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS')['data']
ver = next((v for v in versions if v['attributes']['versionString'] == VERSION), None)
if ver is None:
    ver = must(f'version {VERSION} (new)', call('POST', '/v1/appStoreVersions', {'data': {
        'type': 'appStoreVersions', 'attributes': {'platform': 'IOS', 'versionString': VERSION, 'releaseType': 'AFTER_APPROVAL'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}}}))['data']
vid = ver['id']
print('version', VERSION, ver['attributes'].get('appVersionState'), vid)

vloc = call('GET', f'/v1/appStoreVersions/{vid}/appStoreVersionLocalizations')['data'][0]['id']
must('version localization', call('PATCH', f'/v1/appStoreVersionLocalizations/{vloc}', {'data': {
    'type': 'appStoreVersionLocalizations', 'id': vloc,
    'attributes': {'description': desc, 'whatsNew': news, 'keywords': keywords, 'promotionalText': promo}}}))

rd = call('GET', f'/v1/appStoreVersions/{vid}/appStoreReviewDetail').get('data')
if rd:
    must('review notes', call('PATCH', f'/v1/appStoreReviewDetails/{rd["id"]}', {'data': {
        'type': 'appStoreReviewDetails', 'id': rd['id'], 'attributes': {'notes': notes}}}))
else:
    print('  ! no review detail on this version yet: run listing.py once for the contact details')
