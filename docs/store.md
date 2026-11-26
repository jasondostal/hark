# App Store listing: Hark

**Record created 2026-11-21 by Jason** as **Hark: Listen Closer** (ASC app id 6837884086, SKU `hark`, bundle id
`dev.ducktyping.hark`). App Privacy ("Data Not Collected") and price (Free, every territory except China) set by
Jason in the web UI. `tools/asc/listing.py` pushes the fields below.

## Open before submitting

1. ~~Support and privacy pages~~ LIVE 2026-11-21 at ducktyping.dev/hark/ (no whoami section: that was only for Bent).
2. ~~Screenshots~~ uploaded 2026-11-21. Build 1.0 (1) archived and uploaded 2026-11-21.
3. ~~Submit~~ SUBMITTED 2026-11-21 ~22:50 CST on Jason's go: build 1 attached, version 1.0 WAITING_FOR_REVIEW (review submission 9a1a1cfa-9b83-468f-a21a-33d1c819880f).
   Content rights declared USES_THIRD_PARTY_CONTENT (models, GBIF, OpenFauna, eBird, all licensed; listing.py sets it).
   WITHDRAWN the same night (Jason OK'd): live logging needs tuning first (single-second blips get logged).
   Resubmit = bump CURRENT_PROJECT_VERSION, archive, upload, attach, tools/asc/submit.py <build>.
   RESUBMITTED 2026-11-22 ~21:40 CST on Jason's go: build 3 (Not it + Undo, rare-here flag, ~3 s first launch, on-device copy), WAITING_FOR_REVIEW (submission 3ab2421f-c90c-4b62-9f7a-017e7c5419e7). Upload needs the API key flags (-authenticationKeyPath/-ID/-IssuerID); plain -exportArchive failed 'Failed to Use Accounts'.
4. After approval: set APP_STORE_URL in ducktyping src/pages/hark/index.astro, add Hark to src/lib/apps.ts, deploy.

## Name and subtitle (30 characters each)

- Name: `Hark: Listen Closer` (19)
- Subtitle: `Bird, frog & insect sound ID` (28)

## Promotional text (170; changeable without review)

Two AI models listen at once, all on your iPhone: birds, frogs, insects and mammals, live, even with no signal. Free, no account, no ads. Audio never leaves the phone.

## Description (4000)

Hold up your phone and Hark tells you who's singing: birds, frogs, insects and mammals, live, as they call. Everything runs on the phone. It's free, with no subscription, no account and no ads.

ALL ON YOUR IPHONE
There's no server behind Hark. Two full-size AI models, Google DeepMind's Perch 2.0 and BirdNET+ 3.0, are built into the app and run on your iPhone's Neural Engine, the chip Apple makes for machine learning. Every second, Hark scores the last five seconds of sound against about fifteen thousand species with both models, in a fraction of a second. The species ranges and week-by-week seasons are in the app too. So it works just the same deep in a marsh with no signal or in Airplane Mode, and no recording ever leaves your phone. (The first launch after installing or updating takes a few extra seconds while iOS sets the models up for your phone's chip.)

LIVE
• A scrolling spectrogram and a list of what's calling right now, updated every second
• Full screen: the spectrogram fills the phone, with names over it as they call
• New species are logged as they're heard, with a clip of the call
• "New for you" when a species is a first

TWO MODELS AT ONCE
Google DeepMind's Perch 2.0 and the BirdNET team's BirdNET+ 3.0 listen together. An ID counts when they agree, or when one is very sure. In side-by-side tests that caught more calls than either model alone, with no more false alarms. Prefer one model? Pick it in Settings.

MISSED IT? TOUCH THE SPECTROGRAM
It pauses on the last minute of sound. Drag across a call and Hark identifies exactly that stretch, or tap to grab five seconds. Play it back, see its pitch and length, then log it. Prefer to choose every ID yourself? Manual mode only identifies what you pick out.

POINT COUNTS, SURVEYS, RECORDINGS
• Point count: one spot, a set time, a tally of every species
• Survey: walk a route and Hark maps what you heard along it
• Recordings: pick audio files and Hark identifies what's in them

MORE THAN BIRDS
About fifteen thousand birds, frogs, toads, crickets, katydids, cicadas and mammals worldwide, plus everyday sounds like traffic, dogs and voices, so they don't get mistaken for wildlife. Switch any group off.

KNOWS WHERE AND WHEN
A Spring Peeper in November or a European bird in Wisconsin is flagged as unusual instead of logged, using the BirdNET geomodel's week-by-week ranges and records from GBIF. Add your own free eBird key and anything birders reported near you this month counts too. Species you've confirmed near a spot are never flagged there.

WALK MODE
Start listening, lock the phone and go. Hark keeps logging, shows on the Lock Screen and in the Dynamic Island, and buzzes when something new turns up. It stops on its own after the time you set.

YOUR JOURNAL
• A timeline of everything heard, with time, place, confidence and the clip
• Sessions, with your route on a map and when each species called; name them and add notes
• A species list with your life list growing over time, time-of-day and seasonal charts
• Mark the ones you saw; search and filter by group
• Wrong ID? Swipe "Not it" and Hark drops it and ignores it for the rest of the walk (with Undo)
• Share a card of a find, with the place or without

ONE PRESS
Start listening from the Action Button, Control Center, a widget or Siri.

MAKE IT YOURS
Sensitive, Balanced or Strict, or fine-tune each group. Six looks and nine spectrogram color schemes, including a cream field notebook, an 8-bit one and an all-red one that saves your night vision on an owl prowl. Choose how many seconds the spectrogram shows, its height and contrast, your microphone and its gain, and a high-pass filter for wind and road noise.

PRIVATE
Audio is identified on the phone and never uploaded. No account, no analytics, no tracking. Your journal stays on your phone.

Sound ID can be wrong, especially with distant, quiet or overlapping calls. Treat an ID as a suggestion, and confirm anything important by sight or with an expert.

## Keywords (100, comma-separated; don't repeat name/subtitle words)

`birdsong,birding,bird call,birdwatching,wildlife,nature,spectrogram,owl,toad,cricket,identifier,song`

## URLs

- Support: https://ducktyping.dev/hark/
- Marketing: https://ducktyping.dev/hark/
- Privacy policy: https://ducktyping.dev/hark/privacy/

## Category, rating, price

- Primary category: Reference; secondary: Education
- Age rating: "None" / No throughout → 4+
- Price: Free. Availability: every territory except China (Jason's call).
- Copyright: `2026 Jason Dostal`

## App Privacy (web UI only; set by Jason)

"Data Not Collected". Audio is processed on the device. The only network request Hark makes itself is the optional
eBird lookup with the user's own API key, sent straight from the phone to eBird; the developer receives nothing.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` in the Info.plist (the eBird request is ordinary HTTPS).

## Review notes

Hark needs no login, has no accounts, no content shared between users and no paid features.

1. PURPOSE AND AUDIENCE
Hark identifies wildlife by sound: birds, frogs, insects and mammals. It is for birders, naturalists and anyone curious about what is calling outside. It listens through the microphone, shows a live spectrogram, and identifies calls with two machine-learning models that run entirely on the device (Google DeepMind's Perch 2.0 and BirdNET+ 3.0, both published under the Apache 2.0 license). Detections are kept in a log on the phone with time, place and a short clip. It is free, with no account, advertising or purchases.

2. HOW TO TEST IT
- Open the app and tap the large round microphone button at the bottom. Allow microphone access (and location, optionally).
- Play birdsong from another device near the iPhone. Test recordings are at https://ducktyping.dev/hark/#test-sounds (a Canada Goose, Blue Jay or Barred Owl works well). Within a few seconds the species appears under "Hearing now" and is logged under "This session". The same page has rain, wind and coughing, which should not be logged.
- Touch the spectrogram at the top: it pauses on the last minute of sound. Drag across a call to identify just that stretch; results appear at the top of the list with "Log it" and "I saw it" buttons. "Back to live" returns to the live view.
- The Journal button (bottom left) opens everything Hark has logged (Timeline, Sessions, Species, Map). Settings (bottom right) has the model choice, sensitivity, spectrogram colors and the optional eBird key.
- New in 1.1: the small button above the microphone button picks a mode (Live, Manual, Point count, Survey, Recordings). Recordings opens the system file picker and identifies audio files the user chooses, on the device; nothing is uploaded. The arrows on the spectrogram, or turning the phone on its side, show it full screen with the names of what is calling over it.
No credentials or sample files are needed.

3. BACKGROUND AUDIO (UIBackgroundModes: audio)
Listening only starts when the user taps the microphone button (or the Start Listening control, widget or Siri shortcut). The user can then lock the phone and keep identifying on a walk ("walk mode"): the app keeps recording and analysing audio in the background, logs what it hears, and updates a Live Activity on the Lock Screen and in the Dynamic Island, which has a Stop button. The system microphone indicator is shown the whole time. Listening stops automatically after a user-set time (one hour by default) and whenever the user taps Stop. No audio leaves the device.

4. BACKGROUND LOCATION (UIBackgroundModes: location)
While the user is listening, location tags each detection and draws the route of the listening session, including with the screen locked during walk mode. The app requests When In Use authorisation only; location updates start in the foreground when listening starts and stop when it stops, and iOS shows the location indicator meanwhile. Location also lets the app check identifications against the species expected at that place and time of year. It stays on the device.

5. EXTERNAL SERVICES
None are required. Identification, species ranges (from GBIF data) and seasons (the BirdNET geomodel) are bundled in the app. Optionally, a user can paste their own free eBird API key in Settings; the app then asks eBird (Cornell Lab of Ornithology) which species were reported within 25 km in the last 30 days, sending a location rounded to about 1 km. Maps use Apple MapKit. There is no authentication, payment, analytics, advertising or third-party AI service; the machine-learning models run on the device.

6. REGIONAL DIFFERENCES
The app works the same in every region; which species are flagged as unusual depends on where the user is. The interface is in English.

7. REGULATED INDUSTRY / PROTECTED MATERIAL
Not applicable. Third-party components and their licenses are listed in Settings > About > Acknowledgements.

## Screenshots (6.9", 1320 × 2868)

1.0 (live): five light-mode shots uploaded 2026-11-21 (in git history under `tools/shots/store/`).

1.1 (made 2026-11-25, not uploaded yet): `tools/shots/store/`, in order: full screen with captions, the Listen screen,
a paused selection with results, the Journal timeline, a session with route and chart, the Journal map, the Field
Notebook look (the light one), Settings with the looks. Upload them with `tools/asc/shots.py tools/shots/store/*.png`
once the 1.1 version exists in App Store Connect.

How they're made: the iPhone 18 Pro Max simulator, `simctl status_bar override --time 9:41` (full bars, charged),
`simctl location set 43.4561,-88.6342` (Horicon Marsh), microphone and location granted with `simctl privacy`, and the
Debug build's launch arguments: `-notips -autolisten -feedfile <recordings>` for the live shots (your own recordings,
kept outside the repo; goose, chickadee, robin, crow, cardinal, blue jay in that order, frame taken at about 1:41-1:43
when the jay calls), `-select` for the selection, `-logtab -demolog <folder of recordings>` for the made-up Journal
(`-opensession 2` for the session, `-logmode Map` for the map), `-settings`, and `-theme notebook -palette paper` for
the light one. Timing a live shot is guesswork, so take a burst and pick.

## 1.1 (build 5)

SUBMITTED 2026-11-25 ~12:15 CST on Jason's go (anything found later gets patched in a point release):
build 5 attached, version 1.1 WAITING_FOR_REVIEW (review submission 2f0c50a9-07df-4d91-a935-112a8c38d8d4), releases
automatically on approval. Eight new screenshots uploaded the same day.
APPROVED and on the App Store 2026-11-25 16:09 CST (released 22:09 UTC), about four hours after submitting. The store
shows 1.1, eight screenshots, Reference / Education.
`tools/asc/update.py` makes the version and pushes What's New (below), the description and the review notes; it leaves
app-level fields (categories, age rating) alone. Then `shots.py`, attach the build, `submit.py 5`.

## What's New

Hark 1.1 is a new look and more ways to listen.

• A new look: the whole app is drawn in the colors of the spectrogram you pick, with names in a field-guide serif. Prefer it light? Pick the Field Notebook look or the Paper spectrogram.
• Full screen, redone: the spectrogram fills the phone, what's calling appears as names over it, and earlier species fade below. Tap a name for its buttons, or flick it away if it's wrong. Works upright and on its side.
• Modes: Live as before, plus Point count (stand still for a set time and get a tally) and Survey (walk a route; no time limit, finer track).
• Analyze recordings: pick one audio file or many, and Hark listens to them the way it listens live. Each becomes a session in your Journal.
• The Log is now the Journal. Sessions can have names and notes, and you can share or delete a single one.
• Spectrogram: twice the frequency detail; set its height up to full screen (it zooms in rather than stretching), FFT size, top frequency, background fade and drawing quality.
• Audio: microphone gain, and a high-pass filter you set in Hz.
• Detection tuning: one confidence slider, how often Hark checks, and a setting for the voices-and-music guard.
• Fixes: a siren no longer counts as a salamander.

## 1.1 notes

Ships with it: I-1 (siren), I-2 (OFL texts), I-3 (no selftest audio in the bundle).
TestFlight: 1.1 (4) uploaded 2026-11-25 from 29a11b5, internal group "Me" only (no beta review). The group was made with
automatic distribution off, so each build is added to it by hand; with it on, TestFlight also offered the 1.0 builds.
1.1 (5) uploaded 2026-11-25 from 4402753 and added to the same group.

Never run on a phone before submitting: everything after build 4 (the app-wide look, the Journal rename, the caption
hint, the What's New card). Battery and heat in full screen were not measured either. Jason's call.

The default look (stored as "classic", shown as "Hark") no longer follows the phone's light/dark setting: it follows the
spectrogram's palette, so people updating in light mode get the dark look until they pick Paper or Field Notebook.

Categories: 1.0 went out as Sports / Utilities (listing.py set those, against the section above). Changed to
Reference / Education on 2026-11-25, on the 1.1 version while it waited for review; the store shows the old pair until
1.1 is approved. listing.py now sets Reference / Education too.
