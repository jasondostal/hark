# App Store listing: Hark

**Record created 2026-11-21 by Jason** as **Hark: Listen Closer** (ASC app id 6837884086, SKU `hark`, bundle id
`dev.ducktyping.hark`). App Privacy ("Data Not Collected") and price (Free, every territory except China) set by
Jason in the web UI. `tools/asc/listing.py` pushes the fields below.

## Open before submitting

1. ~~Support and privacy pages~~ LIVE 2026-11-21 at ducktyping.dev/hark/ (no whoami section: that was only for Bent).
2. ~~Screenshots~~ uploaded 2026-11-21. Build 1.0 (1) archived and uploaded 2026-11-21.
3. ~~Submit~~ SUBMITTED 2026-11-21 ~22:50 CST on Jason's go: build 1 attached, version 1.0 WAITING_FOR_REVIEW (review submission 9a1a1cfa-9b83-468f-a21a-33d1c819880f).
   Content rights declared USES_THIRD_PARTY_CONTENT (models, GBIF, OpenFauna, eBird, all licensed; listing.py sets it).
4. After approval: set APP_STORE_URL in ducktyping src/pages/hark/index.astro, add Hark to src/lib/apps.ts, deploy.

## Name and subtitle (30 characters each)

- Name: `Hark: Listen Closer` (19)
- Subtitle: `Bird, frog & insect sound ID` (28)

## Promotional text (170; changeable without review)

Identifies birds, frogs, insects and mammals by sound, live on your iPhone, with two models listening at once. Free, no account, no ads. Audio never leaves the phone.

## Description (4000)

Hold up your phone and Hark tells you who's singing: birds, frogs, insects and mammals, live, as they call. Everything runs on the phone. It's free, with no subscription, no account and no ads.

LIVE
• A scrolling spectrogram and a list of what's calling right now, updated every second
• New species are logged as they're heard, with a clip of the call
• "New for you" when a species is a first

TWO MODELS AT ONCE
Google DeepMind's Perch 2.0 and the BirdNET team's BirdNET+ 3.0 listen together. An ID counts when they agree, or when one is very sure. In side-by-side tests that caught more calls than either model alone, with no more false alarms. Prefer one model? Pick it in Settings.

MISSED IT? TOUCH THE SPECTROGRAM
It pauses on the last minute of sound. Drag across a call and Hark identifies exactly that stretch, or tap to grab five seconds. Play it back, see its pitch and length, then log it. Prefer to choose every ID yourself? Manual mode only identifies what you pick out.

MORE THAN BIRDS
About fifteen thousand birds, frogs, toads, crickets, katydids, cicadas and mammals worldwide, plus everyday sounds like traffic, dogs and voices, so they don't get mistaken for wildlife. Switch any group off.

KNOWS WHERE AND WHEN
A Spring Peeper in November or a European bird in Wisconsin is flagged as unusual instead of logged, using the BirdNET geomodel's week-by-week ranges and records from GBIF. Add your own free eBird key and anything birders reported near you this month counts too. Species you've confirmed near a spot are never flagged there.

WALK MODE
Start listening, lock the phone and go. Hark keeps logging, shows on the Lock Screen and in the Dynamic Island, and buzzes when something new turns up. It stops on its own after the time you set.

YOUR LOG
• A timeline of everything heard, with time, place, confidence and the clip
• Sessions, with your route on a map and when each species called
• A species list with your life list growing over time, time-of-day and seasonal charts
• Mark the ones you saw; search and filter by group

ONE PRESS
Start listening from the Action Button, Control Center, a widget or Siri.

MAKE IT YOURS
Sensitive, Balanced or Strict, or fine-tune each group. Seven spectrogram color schemes, including an all-red one that saves your night vision on an owl prowl. Choose how many seconds the spectrogram shows, its contrast, your microphone and a rumble filter for wind and road noise.

PRIVATE
Audio is identified on the phone and never uploaded. No account, no analytics, no tracking. Your log stays on your phone.

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
- Open the app and tap the large green microphone button at the bottom. Allow microphone access (and location, optionally).
- Play birdsong from another device near the iPhone, for example any recording of a Northern Cardinal, American Robin or Blue Jay. Within a few seconds the species appears under "Hearing now" and is logged under "This session".
- Touch the spectrogram at the top: it pauses on the last minute of sound. Drag across a call to identify just that stretch; results appear at the top of the list with Log and "I saw it" buttons. "Back to live" returns to the live view.
- The Log button (bottom left) opens the detection log (Timeline, Sessions, Species, Map). Settings (bottom right) has the model choice, sensitivity, spectrogram colors and the optional eBird key.
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

Uploaded 2026-11-21, `tools/shots/store/` in order: live listening with "Both models", a paused selection with results,
the log timeline, a session with route and chart, Settings. Made on the iPhone 18 Pro Max simulator (1320 × 2868),
status bar overridden to 9:41, location Horicon Marsh, with `-demolog ~/working/perch-spike/audio_yard` (Debug-only
made-up log) and `-feedfile` yard recordings. The Owling shot was dropped: the owl/peeper recordings render almost
empty in red.
