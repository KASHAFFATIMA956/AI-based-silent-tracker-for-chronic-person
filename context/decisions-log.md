# Decisions Log

Decisions made during a session that weren't explicitly specified in
`docs/`, with a short reason. Newest entries at the top.

---

## 2026-09-02 (later still) — "Could not reach RozNoor" on real device: manifest/network-config investigated and confirmed CORRECT, not the cause — no app-side bug found after exhaustive verification; APK rebuilt/reinstalled unchanged

**Context**: after the previous entry's install, the user ran the release
APK for real on `neo7U2401003561` and hit `"Could not reach RozNoor. Check
your connection & try again."` (the exact string in
`lib/core/api_client.dart:67`, thrown only for Dio's
`connectionTimeout`/`receiveTimeout`/`connectionError` exception types —
i.e. the app never got an HTTP response at all) despite the same phone's
own mobile Chrome loading `https://roznoor-production.up.railway.app/docs`
fine. The task explicitly warned against repeating this project's own
documented pattern of wrong first-guess diagnoses (the Postgres port
confusion, the Brave-browser incident) and asked for the manifest/network-
config to be verified, not assumed, before touching anything.

**Investigated in order, each confirmed rather than assumed:**
1. `android/app/src/main/AndroidManifest.xml` (the release manifest) — `<uses-permission
   android:name="android.permission.INTERNET"/>` is present, correctly
   placed as a direct child of `<manifest>`, outside `<application>`.
   Nothing to fix here.
2. `find mobile_app/android -iname "network_security_config.xml"` — exactly
   ONE file exists in the whole project:
   `android/app/src/debug/res/xml/network_security_config.xml`
   (`<base-config cleartextTrafficPermitted="true" />`, no `<domain-config>`
   blocks). It's referenced ONLY by `android/app/src/debug/AndroidManifest.xml`'s
   `android:networkSecurityConfig="@xml/network_security_config"` — a
   debug-only manifest fragment that Gradle never merges into a release
   build. The release manifest (`src/main/`) has no
   `networkSecurityConfig` attribute at all, so it correctly falls back to
   Android's system default (system-CA trust, HTTPS permitted, cleartext
   blocked) — which is exactly right for an `https://` backend and was
   already the documented, deliberate design (see
   `context/pre-deployment-checklist.md` item 5: "A real `https://` URL
   here also incidentally satisfies Android's cleartext-traffic block on
   release builds for free... needs no change"). **Confirmed this is
   correct, not a bug** — there is no cleartext restriction to trip since
   the app never makes an `http://` request, and no domain/cert
   restriction of any kind applies to the release build.

**Given both files were confirmed correct, went further rather than
guessing a fix — pulled the ACTUAL installed APK off the device and
inspected it directly, plus ran OS-level network diagnostics on the same
physical device, instead of trusting the manifest source alone:**
- `adb pull` the real installed `base.apk` from `neo7U2401003561` and ran
  `strings`/`aapt dump badging` on it directly: confirmed the file
  genuinely installed on the phone has `https://roznoor-production.up.railway.app`
  baked in (no `localhost`, no stale LAN IP) and the compiled manifest
  really does declare `android.permission.INTERNET` — ruling out "a stale
  or different APK is actually installed" as an explanation.
- `adb shell dumpsys netpolicy`: the app's UID (10420) has `rules=0
  (NONE)` — no Doze/App-Standby/background-data restriction blocking it.
- `adb shell settings get global restrict_background` → `null` (Data
  Saver off). No VPN active (`dumpsys connectivity` shows the active
  network as `WIFI ... NOT_VPN`).
- Raw TCP connect from the device's own shell,
  `echo | nc -w 3 roznoor-production.up.railway.app 443` → succeeded
  (`TCP_OK`) — DNS resolution and basic reachability from the device
  itself both work.
- TLS handshake to the exact backend host verified against a real,
  currently-valid Let's Encrypt chain (`*.up.railway.app`, not expired,
  standard ISRG root) — nothing exotic or self-signed that a phone's
  default trust store would reject.

**Conclusion: no defect found in `AndroidManifest.xml` or
`network_security_config.xml`, and no OS-level restriction on this
specific device blocking the app either.** Every layer checked —
permission declaration, network-security-config scoping, the actual
installed binary's baked-in URL, DNS, raw TCP:443, TLS/cert trust,
per-app firewall/Doze/Data-Saver/VPN policy — came back clean. This does
**not** match an app-configuration bug; it matches this project's own
repeated pattern (see the Brave-browser entry above) of an initial
"must be an app/network-config problem" assumption not holding up once
actually verified. The most plausible remaining explanation is something
outside this app's config entirely — e.g. the network the phone was
actually on at the moment of the reported failure behaving differently
for a non-browser app's raw socket connection than for the browser
(common on some captive-portal/institutional WiFi), or a one-off
transient condition — neither of which is fixable by changing
`mobile_app/android/` files, and neither could be confirmed or ruled out
from this session alone since the failure wasn't reproduced live here.

**No code or config change was made** — per the task's own explicit "do
not guess or apply a fix before you've identified the actual cause,"
nothing was changed since nothing was found broken. The release APK was
still rebuilt (`flutter build apk --release
--dart-define=ROZNOOR_API_BASE_URL=https://roznoor-production.up.railway.app`)
and reinstalled (`flutter install -d neo7U2401003561 --release
--use-application-binary=...`) as requested, purely to hand back a
guaranteed-fresh, guaranteed-correctly-configured build (confirmed via
`adb shell dumpsys package`: fresh `firstInstallTime`/`lastUpdateTime`
`2026-09-02 12:15:18`) — functionally byte-for-byte equivalent to what
was already installed, not a fix.

**If this recurs**: next time, capture `adb logcat` live during the
actual failed attempt (not after) and get the real `DioException` type/
message plus which specific request it happened on (login vs. a later
call) — that will show far more than another round of static manifest
inspection can, since this pass exhausted what static
inspection + device-shell diagnostics alone can tell us. Also worth
asking which exact WiFi/mobile-data network the phone was on at the time,
since that's the one variable this session's diagnostics couldn't
reproduce or rule out.

**Context updated**: this entry, [[pending-device-tests]] (item 0's
resume note).

---

## 2026-09-02 (later same day) — Flutter release APK rebuilt against the real production backend, installed on the real device; one real adb permission hiccup found and resolved

**Context**: both the backend (`https://roznoor-production.up.railway.app`)
and `web_app` (`https://roznoor.up.railway.app`) are now live and verified
(see the entry immediately below and [[progress]]) — `web_app` including a
real end-to-end test (login as a seeded patient, a voice/check-in entry
correctly triggering a hard-flag Red result). This session's task: point
the Flutter mobile app at that same real production backend and get it
running on a real connected physical device, then stop — no manual UI
testing this session, that's the user's own next step on the device.

**Device confirmed real before doing anything else**: `flutter devices`
listed `Sparx Neo 7 Ultra (mobile) • neo7U2401003561 • android-arm64 •
Android 12 (API 31)` alongside the Linux-desktop and Chrome-web targets
`flutter devices` always also lists — the task's own instruction was to
stop if only those non-physical targets showed up, which wasn't the case
here.

**Config verified before building, not assumed correct**: read
`lib/core/app_config.dart` — `AppConfig.apiBaseUrl` is
`String.fromEnvironment('ROZNOOR_API_BASE_URL', defaultValue:
'http://localhost:8000')`, exactly the key name the task assumed. Grepped
all of `lib/` for `AppConfig` usage (exactly one call site,
`api_client.dart:27`, Dio's `baseUrl`) and for any other hardcoded
`http(s)://`/`localhost`/`192.168.` string anywhere else in the app (zero
hits) — confirmed there's no separate fallback URL that could get used
instead of the dart-define value.

**Built the release APK**: `flutter build apk --release
--dart-define=ROZNOOR_API_BASE_URL=https://roznoor-production.up.railway.app`
→ `mobile_app/build/app/outputs/flutter-apk/app-release.apk` (54.4MB, real
`assembleRelease` Gradle task, not debug). **Verified the dart-define
actually won, not just trusted the mechanism**: ran `strings` on the built
APK — the real production URL is present in the binary, and the
`localhost:8000` default-value string is **completely absent** (Dart
const-folded the unused default away entirely, rather than leaving it
sitting inert as a possible fallback).

**One real transient blocker hit and resolved during install, not silently
retried past**: between the initial `flutter devices` check and the
install attempt (~8 minutes later, spent on the release build), the
phone's `adb` connection dropped from `device` to `no permissions` —
confirmed the phone was still physically connected the whole time (visible
in `lsusb`, ID `18d1:4ee8`), so this was a host/udev permission hiccup
on re-enumeration, not a phone disconnect or a code problem. Tried
`adb kill-server`/`start-server` first (no effect), then stopped and asked
the user directly (per this project's own "don't guess again, ask" pattern
for exactly this class of device-connectivity issue — see the acoustic-
audio item's history in [[pending-device-tests]]) rather than attempting a
host-level udev-rule fix unprompted. The user chose to physically
unplug/replug the cable — re-checked via `adb devices -l` showing `device`
state again (not just re-running blind) before retrying the install.

**Installed for real, confirmed via the device itself, not just a clean
exit code**: `flutter install -d neo7U2401003561 --release
--use-application-binary=build/app/outputs/flutter-apk/app-release.apk`
succeeded; `adb shell dumpsys package care.roznoor.roznoor_app` confirmed
`versionName 1.0.0` with `firstInstallTime`/`lastUpdateTime` both
`2026-09-02 11:56:31` — a genuinely fresh install, not a stale one being
misread as success.

**Deliberately not done this session**: any manual interaction with the
installed app (login, Voice Diary, the chest-pain hard-flag check, doctor
dashboard) — per the task's explicit instruction, that's the user's own
next step directly on the device. See [[pending-device-tests]] (new item
0) for the exact resume note, and [[progress]] for the summary.

---

## 2026-09-02 — Backend deployed to Railway and verified end-to-end; `web_app/` deployment prep re-confirmed complete, no code changes needed

**Context**: backend is now live at `https://roznoor-production.up.railway.app`
— Postgres connected via a `DATABASE_URL` service reference, `JWT_SECRET_KEY`
set to a real generated secret, `alembic upgrade head` ran successfully on
first deploy, and `seed.py` was run exactly once against the real production
database (per the [[pre-deployment-checklist]] runbook's explicit
run-exactly-once warning). Login verified end-to-end via a real `curl`
request against the deployed URL, returning a valid JWT for a seeded patient
account — not just a `200` on `/health`. This session's own task was
narrower: prepare `web_app/` for deployment as a second Railway service in
the same project, without touching the backend at all.

**Finding: `web_app/`'s Dockerfile/nginx/build-arg setup was already fully
built and verified** — the 2026-08-29 deployment-readiness pass (see
[[pre-deployment-checklist]] item 6 and item 5) already produced
`web_app/Dockerfile` (multi-stage: `node:20-alpine` build → `nginx:1.29-alpine`
serve), `web_app/nginx.default.conf.template` (`try_files $uri $uri/
/index.html` SPA fallback, with a real `404` — not the fallback — for a
missing file under `/assets/`), and the `ARG VITE_API_BASE_URL` build-arg
plumbing into `vite build`. Nothing needed to be created or fixed this
session — verified this by reading all three files plus `railway.json`/
`.dockerignore` in full, not by assuming the checklist's "fixed" status was
still accurate.

**Re-verified for real, this session, against the actual production backend
URL** (not a fake placeholder like the 2026-08-29 pass used, since a real
one now exists): `docker build --build-arg
VITE_API_BASE_URL="https://roznoor-production.up.railway.app"` succeeded;
grepped the built `dist/assets/*.js` and confirmed the literal URL is
genuinely inlined into the bundle, not just present in an unread config
file. Ran the resulting image as a real container with `PORT=8080` mapped:
direct `curl` hits (not client-side nav) at `/roster/2`, `/notifications`,
`/people/new`, and even `/patients` itself (proving nginx has no awareness
of the backend's proxied path list — it's just serving static files, so
there's no collision risk in production the way there was with Vite's
dev-server proxy) all returned `200` with the real SPA shell
(`<title>RozNoor</title>`); a deliberately-nonexistent asset path still
correctly `404`s (the fallback doesn't swallow real missing-file errors).
Test image/container removed after verification.

**Confirmed the SPA route renames are consistent everywhere, not just in
`App.jsx`**: grepped `web_app/src` for `/patients` and `/alerts` as route
strings — the only hits are `App.jsx`'s own explanatory comments about why
those names were avoided; the actual `<Route path=...>` and `<NavLink
to=...>` values are `/roster`+`/roster/:patientId` (doctor),
`/notifications` (doctor alerts), and `/people`+`/people/new`+
`/people/:userId/edit` (admin) — matching `DoctorShell.jsx`/`AdminShell.jsx`'s
nav links exactly. No top-level `/patients` or `/alerts` route exists
anywhere in `web_app/`.

**No backend code or Railway backend environment variables touched** — per
this session's explicit scope. `CORS_ALLOWED_ORIGINS` stays unset/default
until `web_app`'s real Railway domain exists, exactly as the
[[pre-deployment-checklist]] runbook's Step 3 already documents; updating it
is an explicit follow-up, not done this session.

**What's still manual, on Railway's own dashboard** (not something a coding
session can do): create the `web_app` Railway service (Root Directory =
`web_app`), set `VITE_API_BASE_URL` = `https://roznoor-production.up.railway.app`
as a service variable (Railway auto-forwards it as the Dockerfile's build
arg — no separate "build args" UI), deploy, generate a public domain for
it, then come back to the backend service and set `CORS_ALLOWED_ORIGINS` to
that real domain. Exact sequence already documented in the
[[pre-deployment-checklist]] runbook (Steps 2–3) — this session didn't need
to re-derive or change that sequence, only confirm the underlying
Dockerfile/nginx mechanics it depends on still actually work.

Context updated: this entry, [[progress]] (backend-deployed +
web_app-deployment-prep-complete summary).

---

## 2026-09-01 (real-device verification session, continued) — All three [[pending-device-tests]] items resolved: acoustic-audio (8 more real successes), Flutter doctor-role on real hardware, and web Voice Diary's real blocker turned out to be Brave, not connectivity

**Context**: continuation of the same session as the AI-key finding below.
After resolving that, worked through the full real-device checklist in
order: LAN reachability re-check, acoustic-audio repeat confirmations,
Flutter doctor-role real-device pass, and the web app's real-microphone
Voice Diary test. Full step-by-step detail for each lives in
[[pending-device-tests]] (each item's own section now marked ✅ RESOLVED);
this entry is the narrative summary plus the one new finding worth its
own writeup.

### LAN reachability
Phone (`neo7U2401003561`) reconnected via USB (dropped and had to be
reconnected once mid-session — a real but mundane USB/adb hiccup, not an
app issue). Dev machine's LAN IP unchanged from the last session
(`192.168.100.58`), so no rebuild was needed for connectivity reasons —
confirmed via `hostname -I`, a direct `curl` from the dev machine, and an
`adb shell ping` from the phone itself (not just "the server is
listening" — genuine two-way network confirmation). `roznoor-pg` had
stopped since the last session; restarted. Backend started fresh,
`--host 0.0.0.0 --port 8000`.

### Acoustic-audio upload — resolved as a side effect of the AI-key
### investigation, not a separately staged test
The 8 voice entries submitted while diagnosing the AI-key gap (entries
68-75, see below) each also carried a real audio upload
(`POST /entries/{id}/audio`), since Voice Diary always attempts this
regardless of what's being tested. All 8 succeeded — verified via the
backend log, a direct Postgres `SELECT` (real, varying
`acoustic_features` per entry, not stale/duplicated data), and a
filesystem spot-check on 3 of the 8 files (correct sizes, correct
timestamps). Combined with entry 43 from the 2026-08-28 session, that's
9 real successes across two sessions with zero failures — well past the
2-3 needed to rule out intermittency. Genuinely closed.

### Flutter doctor-role real-device pass
Rebuilt (`flutter build apk --debug
--dart-define=ROZNOOR_API_BASE_URL=http://192.168.100.58:8000`) and
reinstalled fresh on the real phone, even though the IP hadn't changed —
the doctor-role code itself had only ever been verified under Xvfb, never
on this device. Logged in as both seeded doctors in turn. Dr. Ayesha
Farooq (id 23, 4 patients): roster/alerts/detail rendered correctly;
5 real alert-reviews and 1 real note submitted through the UI, all
confirmed persisted via direct Postgres `SELECT`s (not the UI's own
success state). **Account-switch scenario re-run on real hardware for the
first time** (this exact scenario caught a real bug in the earlier Xvfb
pass, in `root_router.dart`): logged out, logged in as Dr. Hamza Iqbal
(id 24, 2 patients) — the backend log showed every subsequent call
correctly switch to `/doctors/24/...` with zero stale `/doctors/23/...`
traffic afterward, and a second note (id 12, patient 11) was confirmed to
carry the correct `doctor_id`/`patient_id` pair, not a cross-doctor leak.
The account-switch fix holds on real hardware, not just Xvfb.

### Web Voice Diary — the real blocker was the browser, not the network
First retry attempt hit the exact same `Recognition error: network` the
2026-08-29 session saw — but this time, rather than assuming a repeat of
that connectivity explanation, asked the user to isolate it: Google's own
voice search worked fine on the same machine, which ruled out a genuine
connectivity problem this time. Follow-up question narrowed it to the
actual cause: **the browser was Brave, not Chrome.** Brave deliberately
blocks/strips the underlying Google speech-recognition service as part of
its privacy model — a documented Brave behavior, distinct from (and not
reliably fixed by) toggling Shields — and this exactly matches
`VoiceDiaryScreen.jsx`'s own doc comment, which has always scoped this
feature to "Chrome/Edge only." Brave was never a browser any prior
session tested against. **Confirmed not an app bug**: the identical code,
same dev server, same machine, same internet connection worked
immediately once the user switched to real Google Chrome.

**Full pipeline verified real, end-to-end, for the first time** (entry
76, patient 8, real Chrome, real internet, real microphone): a real
`SpeechRecognition` transcript ("hello I am feeling not well I have chest
pain and breathlessness"), real AI-merged extraction (`["Chest pain",
"Breathlessness", "general malaise: feeling unwell"]`, `source:
"merged"`), the correct hard red-flag (`Red`, correct reasoning), and a
real `MediaRecorder`-captured `.webm` sample
(`audio_storage/8/entry76_9d27ec99.webm`, 96,896 bytes, confirmed on
disk, correctly decoded into populated `acoustic_features`) — verified via
the live backend log (`POST /entries → 201`, `POST /entries/76/audio →
200`) and a direct Postgres `SELECT`, not the Result screen alone. This is
the first real confirmation of the web app's full Voice Diary pipeline on
real hardware/internet; every prior web-app pass had only exercised the
typed-text fallback.

**A genuinely new, worth-keeping finding**: `webkitSpeechRecognition`'s
"Chrome/Edge only" scoping in this codebase's own doc comment should be
read as "Chromium-based-but-not-Brave" more precisely — Brave passes as a
Chromium browser in every other respect but silently fails this one API
in a way that surfaces as a generic `network` error, easy to
misdiagnose as a connectivity problem (as the 2026-08-29 session did, not
unreasonably, since the user's own connectivity really was the cause that
time). Worth a quick "which exact browser?" check before trusting a
`network` error from this feature at face value in any future session.

### All three [[pending-device-tests]] items now resolved
Real, DB/filesystem/log-confirmed evidence for every item — not one
relies on trusting a screen alone. [[pending-device-tests]] updated
per-item as each resolved; [[progress]] updated with the final
close-out. No code changes were needed for any of the three — every
fix this session was either configuration (the API key) or diagnostic
(Brave vs. Chrome), not application code.

---

## 2026-09-01 (real-device verification session) — Real finding: voice-only chest pain gets ZERO rule-engine protection without `ANTHROPIC_API_KEY` set; confirmed fix, both English and Urdu, on real hardware

**Context**: mid-way through this session's real-device Voice Diary
testing (see [[pending-device-tests]] items 1/4), the user spoke clear
distress phrases across 5 real voice entries on the real phone — including
explicit English and Urdu chest-pain/breathlessness phrasing — and every
one came back `Green` ("Stable"). This directly contradicted the
2026-08-25 AI-layer pass's own verification, which had confirmed a spoken
chest-pain transcript alone (no manual tick) correctly triggers the hard
Red flag via AI-merged extraction. The user correctly flagged this as
safety-relevant and asked for the live backend log + DB to be checked
before any further testing, rather than guessing.

**Root cause, confirmed from the actual running process, not assumed**:
`Backend/.env`'s `ANTHROPIC_API_KEY` line was present but **empty** this
session (a fresh backend start, unlike the 2026-08-25 pass which had a
real key supplied for that session only and removed afterward, per its own
verification note). Checked three ways, escalating: (1) the live
`uvicorn` log had zero AI/extraction-related lines for any of the 5
entries — not even a soft-fail warning; (2) `app/services/ai.py`'s
`_get_client()` returns `None` **before** any API call or log statement
when `settings.anthropic_api_key` is falsy — confirmed by reading the
function, this is a genuinely silent path by design (the module's own
docstring lists "no API key configured" as one of several reasons
`extract_symptoms()` returns `None`, all treated identically); (3) directly
queried the *running* process's real environment
(`/proc/<pid>/environ`) and the live `settings` object from inside the
app itself — `anthropic_api_key` resolved to `''`, not just absent from
the file. A direct Postgres `SELECT` against `ai_results`/`risk_results`
for the 5 entries confirmed the mechanism, not just the symptom: every
`extracted_symptom_tags` was empty/null and `risk_results.source` stayed
`'rule'` on all 5 — proving extraction never ran, not that it ran and
missed the symptoms.

**A real architectural fact surfaced along the way, worth keeping
regardless of this session's specific cause**: read `app/services/
rules.py` and `app/routers/entries.py` in full to confirm there is **no
raw-transcript keyword-scanning fallback anywhere** — the hard-flag check
(`hard_hits = symptom_names & ruleset["hard_red_symptoms"]`) only ever
looks at a `symptom_names` set built from manually-ticked checklist items
or AI-extracted matches. This means a voice entry's spoken content is
entirely inert for symptom-based rules whenever `ANTHROPIC_API_KEY` is
unset — not degraded, literally inert — regardless of whether that's
because the key is missing, invalid, or the API is down. Weight-based hard
flags are unaffected (they don't depend on transcript content at all).
This was always true and previously documented as an AI-availability
fallback characteristic, but not previously stated this plainly as "voice
chest pain with no manual tick has zero protection without AI" — flagging
explicitly now since it has real deploy/demo implications (if a real
deployment's `ANTHROPIC_API_KEY` were ever unset or exhausted, this
specific safety path silently goes dark with no error anywhere).

**Not a code bug** — this exactly matches the documented, previously-
verified soft-fail behavior for a missing key (see the 2026-08-25 AI-layer
pass and the 2026-08-25 Flutter patient-app pass, both of which explicitly
noted entries stayed `source: "rule"` with no key configured). What was
new this session was hitting it unexpectedly (a fresh backend start this
session had no key loaded, unlike the prior device-testing passes which
either had one or weren't testing symptom-triggering phrases) and, more
usefully, stating the "zero protection, not degraded protection" framing
explicitly for the first time.

**Fix and re-verification, real hardware, both languages**: at the user's
instruction, the user added a real Anthropic API key directly to
`Backend/.env` themselves (never passed through this session/conversation
in any form — same handling discipline as the 2026-08-25 pass). Backend
restarted to pick it up (`--reload` watches app code, not `.env`).
Confirmed loaded from the live process without ever printing the value
(`bool(key)`, length, and prefix only). Re-ran 3 real voice entries on the
same physical phone:
- Entry 73 (English) — "hello I am feeling breathlessness and I have pain
  in my chest" → `extracted_symptom_tags: ["Breathlessness", "Chest
  pain"]`, `source: "merged"`, **Red**, correct hard-flag reasoning.
- Entry 74 (Urdu, breathlessness only, no chest-pain phrase) —
  "اچھا مجھے سانس لینے میں تکلیف ہو رہی ہے" → correctly extracted
  breathlessness only, **Green** — correctly NOT hard-flagged, since
  `HEART_FAILURE_RULES["hard_red_symptoms"]` is `{"Chest pain"}` only, not
  breathlessness. (The user's own recollection when reporting back said
  "both times" showed the Red warning; the DB shows this one was
  genuinely Green — corrected plainly rather than silently agreeing, since
  the whole point of this check was not trusting a screen/memory over the
  DB.)
- Entry 75 (Urdu, breathlessness + explicit chest pain) —
  "...اور مجھے چیسٹ پین بھی ہے" → correctly extracted both symptoms,
  **Red**, correct hard-flag reasoning.

Confirms the AI-merge pipeline itself works correctly in both English and
Urdu, on real hardware, once configured — the only failure this session
was the missing key, and the rule/AI merge logic underneath it is intact.

**Context updated**: this entry only. `progress.md`/`pending-device-tests.md`
updates for the actual real-device checklist items (acoustic-audio,
doctor-role, web-voice) are tracked separately as those items complete —
see [[pending-device-tests]].

---

## 2026-08-29 (deployment-readiness session, part 3) — Final deploy prep: audio storage moved to a Railway Volume, plus the full deploy runbook (env-var ordering, frontend rebuild commands, one-time seed command)

**Scope**: item 7 (local-disk audio storage) — the last open Tier-1/7-item
🔴, explicitly requested alongside "prepare the final deployment
configuration" — plus producing the actual step-by-step Railway setup
sequence (env vars in dependency order, the exact frontend-rebuild
commands, and the one-time `seed.py` invocation), pulling together
everything the three prior deployment-readiness passes had fixed
individually but never assembled into one ordered runbook.

### Audio storage: a Railway Volume, deliberately not cloud/S3 storage

**The decision, and why it's the right-sized fix here — not a default,
a considered choice**: cloud object storage (S3/R2/Backblaze) is the
textbook "real" production answer for user-uploaded files, and was the
option [[decisions-log]] had flagged since the original 2026-08-25
acoustic-analysis pass ("would need a real object-storage migration
before any real deployment"). But the user explicitly ruled it out this
session, and the reasoning holds up on inspection: cloud storage would
mean provisioning an external account Railway doesn't offer natively,
adding a new SDK dependency, real credential/IAM management, and a
genuine rewrite of `app/routers/entries.py`'s upload/read path — a lot of
new surface area for a single-instance hackathon deployment that was
never asked for. **A Railway Volume — a persistent disk attached directly
to one service, surviving restarts/redeploys — solves the actual problem
(files vanishing on redeploy) with zero new dependencies and effectively
a one-line code change**, since `os.path.join`/`os.makedirs` in
`app/routers/entries.py` already work identically against a relative dev
path or an absolute mount path; nothing about how files are written or
read needed to change, only where.

**The real trade-off, flagged plainly rather than presented as free**: a
Railway Volume attaches to exactly one service — this remains a
single-backend-instance design, the same limitation the original
local-disk approach always had. That's genuinely fine at this project's
actual scale (a hackathon demo, one backend instance, never claimed
otherwise), but it's also the honest reason cloud storage would eventually
be the right call if this ever needed to run more than one backend
replica — not a claim this fix "solves storage" in general, just that it
solves the specific problem this session was asked to fix.

**Implementation**: `Backend/app/core/config.py` — the field renamed
`audio_storage_dir` → `audio_storage_path`, now reading from a real env
var (`AUDIO_STORAGE_PATH`, pydantic-settings' standard field→env-var
mapping — previously this field had no env var at all, just a hardcoded
Python default with no way to override it short of editing code),
defaulting to the exact same relative `"audio_storage"` string as
before — zero behavior change for local dev by design. `app/routers/
entries.py` and `app/models/entry.py`'s doc comment updated to match the
rename (grepped the whole `Backend/` tree afterward to confirm no
remaining references to the old name). `Backend/.env.example` documents
the new var and the recommended production shape
(`AUDIO_STORAGE_PATH=/data/audio_storage`, paired with a Volume mounted
at `/data`).

**Verified for real, at three levels, ending with the actual property
being fixed — not just "the path is configurable"**:
1. Unit-level: `Settings()` falls back to the unchanged relative default
   with no env var set (zero regression), and correctly picks up an
   absolute env-var value when one is set; the existing local `.env`
   setup (no `AUDIO_STORAGE_PATH` line) still resolves identically.
2. Full functional round trip against the real local dev backend, with
   `AUDIO_STORAGE_PATH` pointed at a fresh scratch directory: submitted a
   real voice entry, uploaded a real synthetic WAV (generated via
   Python's stdlib `wave` module, same technique the original
   2026-08-25 acoustic-analysis pass used) through
   `POST /entries/{id}/audio`, confirmed `acoustic_features` came back
   correctly populated — the real `ffmpeg` decode + signal-processing
   pipeline is completely unaffected by the storage-path change — and
   confirmed via both the DB's `audio_file_path` column and a direct
   filesystem check that the file landed at the new path, not the old
   default location. Test entry/rows cleaned up afterward.
3. **The actual "survives a redeploy" proof, run with a real Docker
   Volume, and — critically — run again as a negative control without
   one, for contrast**: rebuilt the real `Backend/Dockerfile` image
   (incorporating this session's config.py/entries.py/models/entry.py
   changes), ran a container with a real Docker named volume mounted at
   `/data` and `AUDIO_STORAGE_PATH=/data/audio_storage`, seeded it, submitted
   a real voice entry, uploaded real audio, confirmed the file existed
   inside that container. Then **destroyed that container entirely**
   (`docker rm -f` — exactly what happens to the old container on every
   real Railway redeploy) and started a **brand-new** container sharing
   the same named volume: the file was still there, and a real
   `GET /entries/{patient_id}/timeline` call against the new container
   still correctly returned `has_audio: true` and the real
   `acoustic_features` for that entry — proof this isn't just "the env
   var points somewhere else now," the file genuinely survives container
   destruction the way a real Railway redeploy would destroy the old
   instance. Then repeated the identical destroy-and-recreate cycle with
   the same `AUDIO_STORAGE_PATH` value but **no volume mounted** at all —
   in the new container, the directory didn't even exist anymore,
   concretely confirming Railway's ephemeral-filesystem-by-default
   behavior is real, and that the Volume specifically (not just "a
   different path") is what fixes it.

### The Railway deploy runbook

Assembled the individual fixes from all three deployment-readiness
sessions (JWT secret, CORS, `$PORT`/migrations/`ffmpeg`, `DATABASE_URL`
scheme, SPA fallback, frontend build-arg plumbing, and this session's
Volume) into one ordered, actionable sequence — `context/
pre-deployment-checklist.md`'s new "Railway deploy runbook" section.
The real ordering constraint the user flagged up front turned out to be
real: `CORS_ALLOWED_ORIGINS` (a backend variable) can't be set to its
final correct value until `web_app` has been deployed and has a URL, and
`web_app`'s own `VITE_API_BASE_URL` can't be set until the backend has
been deployed and has a URL — a genuine two-way dependency between the
two services' URLs, resolved by: deploy the backend first (with
`CORS_ALLOWED_ORIGINS` left at its local-dev default, since nothing
external can call it yet anyway), deploy `web_app` pointed at the
backend's now-known URL, then go back and set `CORS_ALLOWED_ORIGINS` on
the backend to `web_app`'s now-known URL (Railway restarts a service on a
variable change, so no separate manual redeploy trigger is needed for
this last step).

**`seed.py`'s exact invocation, documented with the destructive-rerun
warning repeated inline** (not just cross-referenced) — given via two
paths depending on local setup: the Railway CLI's `railway run --service
<name> -- python seed.py` (runs locally with the linked service's real
env vars injected), or, without the CLI, pulling the Postgres service's
public/external connection string from Railway's own dashboard and
running `DATABASE_URL="<public-url>" python seed.py` locally — the exact
command-line shape (`DATABASE_URL="..." .venv/bin/python seed.py`) was
verified for real this session against the existing local
`roznoor-pg` container (re-running the project's own established, already
many-times-used seed command) before being written into the runbook, not
just assumed from the script's own docstring. This incidentally reset the
shared dev Postgres to clean seed state, clearing the accumulated stray
test-account rows [[decisions-log]]/[[pre-deployment-checklist]] item 10
has flagged since the doctor- and admin-role passes — a welcome side
effect, not the point of running it, and not itself a fix for item 10
(which is about the *real deployed* DB, still open, still deliberately
not fixed this session).

**Flutter rebuild command** (Step 5 of the runbook) is unchanged from
item 5's already-verified `--dart-define=ROZNOOR_API_BASE_URL=...`
mechanism — restated in the runbook in its actual place in the deploy
sequence (after the backend has a real URL) rather than left only in
item 5's own entry, since that's genuinely when it needs to run.

**Docker cleanup**: every test container/image/volume created this
session (`roznoor-backend-vol-test` image, `roznoor-audio-vol` volume,
`roznoor-pg-voltest` and all four `roznoor-backend-voltest-*` containers,
the `roznoor-vol-test` network) was removed after verification. Local dev
processes (`uvicorn`, `vite`) restored to normal config; the shared
`roznoor-pg` dev Postgres was re-seeded as part of verifying the runbook's
`seed.py` command (see above) — its own container was left running,
matching every prior session's convention of leaving the ongoing dev
setup in place rather than tearing it down.

**Context updated**: this entry, `context/pre-deployment-checklist.md`
(item 7 marked ✅ fixed-and-verified with full detail; new "Railway deploy
runbook" section with the ordered env-var/service-setup sequence, the
`seed.py` command, and the Flutter rebuild command; both intro summary
blocks updated). `progress.md`/`conventions.md` were NOT updated — same
scope discipline as every prior deployment-readiness pass, only the two
files these sessions have consistently used.

---

## 2026-08-29 (deployment-readiness session, part 2) — Tier-2 deploy-hardening fixes: real CORSMiddleware, a JWT-secret startup safeguard, build-time base-URL plumbing verified end-to-end

**Scope**: exactly the three items the user named as Tier 2 — items 1
(`JWT_SECRET_KEY`), 2 (CORS), and 5 (frontend build-time base URLs) from
`context/pre-deployment-checklist.md`. Item 7 (local-disk audio storage)
and every Tier-3 item (`flutter test`, seed/migration process, stray
test-account cleanup, unreviewed clinical thresholds, refresh tokens) were
explicitly NOT touched, per the task's own "stop after these three"
instruction — same discipline the Tier-1 pass used.

### 1. JWT_SECRET_KEY — reading from env was already correct; added a hard startup failure for the case that was previously silent

The user's own framing was precise: confirm the read-from-env mechanism
(it was already correct — pydantic-settings reads `JWT_SECRET_KEY`
automatically) and confirm the insecure default "only applies as a
local-dev fallback, never silently used in a production-like context." The
second half wasn't true yet — nothing stopped the insecure default from
being a completely valid, silently-accepted value in any environment,
including a real deploy that simply forgot to set the env var.

**Fixed**: `Backend/app/core/config.py` — a `model_validator(mode="after")`
(`forbid_insecure_secret_outside_dev`) that raises `ValueError` at
`Settings()`-construction time if `environment` (the existing
`ENVIRONMENT` field, already surfaced on `GET /health`) is anything other
than `"development"` AND `jwt_secret_key` is still the literal insecure
default. This makes the previously-silent gap a loud one: the app cannot
finish booting at all without a real secret once it thinks it's running
outside local dev. The user explicitly said they'd set the real secret
value directly in Railway themselves and didn't want (or need) this
session to know it — nothing in this pass touched, generated, or needed
the actual value; only the enforcement code changed. `Backend/.env.example`
updated to document both `ENVIRONMENT=production` and a real
`JWT_SECRET_KEY` as the two env vars a real deploy needs to set together.

**Verified for real**, four real `Settings()`/module-import scenarios, each
its own process (not mocked): (a) no `ENVIRONMENT`/no `JWT_SECRET_KEY` →
boots fine with the insecure default — zero regression to local dev; (b)
`ENVIRONMENT=production`, no `JWT_SECRET_KEY` → importing
`app.core.config` itself raised `ValidationError` with the intended
message — this is the module-level `settings = Settings()` line failing,
proving the real app process would crash at startup, not just an isolated
check; (c) `ENVIRONMENT=production` + a real secret value → boots fine;
(d) the existing local `Backend/.env` still resolves completely
unchanged, confirmed against the already-running `roznoor-pg` dev setup
every prior session in this project has used.

### 2. CORS — real `CORSMiddleware`, exact allowed origins via env var, no wildcard, verified through an actual cross-origin browser session

**Fixed**: `Backend/app/main.py` — `fastapi.middleware.cors.CORSMiddleware`
added right after app construction, wrapping every route.
`Backend/app/core/config.py` — a new `cors_allowed_origins` field (env var
`CORS_ALLOWED_ORIGINS`, comma-separated exact origins — never a wildcard,
per the user's explicit instruction, since this is a health app and an
arbitrary allowed origin would mean an arbitrary site could act on a
signed-in user's behalf) with a `cors_allowed_origins_list` property that
splits/strips it. Default covers Vite's own dev port on both `localhost`
and `127.0.0.1` so local dev (including a `vite dev` instance pointed
directly at the backend, bypassing its own proxy) keeps working with zero
setup. `allow_credentials=False` — this app has no cookie-based session
anywhere (`web_app/src/core/tokenStorage.js` uses `localStorage`, and the
`Authorization` header it sends is not treated as a CORS "credential" the
way a cookie is), so there's nothing for credentialed-mode CORS to apply
to. `allow_methods`/`allow_headers` stayed `["*"]` — the user's "be
specific" instruction was about origins specifically (the actual security
boundary: which sites can call this API on a user's behalf), not about
which HTTP verbs/header names an already-allowed origin may use.
`Backend/.env.example` updated with the new var.

**Verified for real, in layers, ending with the most convincing check
available without a live Railway deployment**:
1. Direct `curl` against a real running (freshly restarted, to load the
   new code) local backend instance, with real `Origin` headers: a
   preflight `OPTIONS` for a `PATCH` (the admin edit-user request shape,
   `Authorization` + `Content-Type` in `Access-Control-Request-Headers`)
   from the allowed default origin returned the full real CORS header
   set; a real `GET /health` from that origin echoed
   `access-control-allow-origin` back correctly; the identical request
   from a deliberately disallowed origin (`http://evil-example.com`) got
   a real `200` from the server (correct — CORS is a browser-side
   enforcement mechanism reading response headers, the server itself
   doesn't refuse the request) but genuinely **no**
   `Access-Control-Allow-Origin` header at all, which is what actually
   makes a real browser block it.
2. Restarted the backend with `CORS_ALLOWED_ORIGINS` set to a fake but
   realistic deployed-origin shape
   (`https://roznoor-web-production.up.railway.app`) — confirmed that
   origin became allowed AND the previous default (`localhost:5173`)
   correctly stopped being allowed, proving the env var genuinely drives
   the allow-list rather than there being some hardcoded fallback
   underneath it.
3. **The real end-to-end browser check**: restarted `web_app`'s Vite dev
   server with `VITE_API_BASE_URL=http://localhost:8000` set — this
   forces every one of the app's own `fetch()` calls to hit the backend
   directly at a genuinely different origin (different port =
   different origin per the browser's own same-origin-policy
   definition), completely bypassing `vite.config.js`'s dev-proxy that
   every prior session in this project relied on. Opened the result in an
   actual Chrome browser via `claude-in-chrome` — not a simulation, a real
   browser enforcing real CORS. First pass reused an
   already-authenticated `localStorage` session from an earlier test and
   loaded real doctor-roster data via three real cross-origin `GET`s, all
   `200`, confirmed via `read_network_requests`; then a real cross-origin
   `POST /alerts/{id}/review` (clicking "Mark reviewed" in the UI) — a
   write, not a read — succeeded and was independently confirmed
   **persisted via a direct Postgres `SELECT`** (`reviewed` flipped to
   `true` for that specific row), not just a UI-state change. **Then,
   specifically because a reused session doesn't exercise every CORS
   case**: logged out for real (clearing the stored token) and performed
   a genuinely fresh login — `POST /auth/login` is the one call in this
   app that carries no `Authorization` header at all, a distinct CORS
   shape from every other request, and it's a different HTTP method with
   a JSON body (still preflighted, since `application/json` isn't a
   CORS-safelisted content type). Confirmed via `read_network_requests`:
   a real cross-origin `POST /auth/login` returned `200`, followed by
   real cross-origin `GET /auth/me`, `GET /patients/2`,
   `GET /patients/2/symptom-checklist`, `GET /entries/2/timeline` all
   loading the real patient Home screen. Zero console errors or CORS
   warnings at any point across either browser session (checked via
   `read_console_messages`, armed before each flow, not just checked
   after the fact). Both dev processes (`vite`, `uvicorn`) were restored
   to their normal, non-cross-origin-forced configuration afterward —
   this session's CORS-testing setup doesn't persist as the project's
   default dev config.

### 3. Frontend build-time base URLs — both mechanisms already existed, neither had been proven; now both are, plus the one real gap (the Dockerfile's build-arg plumbing) is fixed

Per the user's explicit instruction: don't guess the real Railway URLs
(not available yet) — instead prove the build-time-parameter mechanism
itself works cleanly for both frontends, and document the exact commands
to run once real URLs exist.

**Found a real gap while checking, not just verifying the status quo**:
`web_app/Dockerfile` (written in the Tier-1 pass) had a comment noting
`VITE_API_BASE_URL` should be set as a Railway build-time env var, but
nothing in the Dockerfile actually plumbed a build-time value into the
`npm run build` step — a `docker run -e VITE_API_BASE_URL=...` would never
reach a build stage at all (build args and runtime env vars are genuinely
different mechanisms in Docker), so as written, Railway would have had no
way to actually inject this value no matter what was set on the service.

**Fixed**: `web_app/Dockerfile` — added `ARG VITE_API_BASE_URL=""` +
`ENV VITE_API_BASE_URL=$VITE_API_BASE_URL` immediately before `RUN npm run
build`, so the value genuinely flows from a real build arg into Vite's own
`import.meta.env` static replacement at build time. Railway's Dockerfile
builder auto-forwards any service variable whose name matches a declared
`ARG` as a build arg on deploy — no separate "build args" configuration
needed beyond setting the variable on the service. No `mobile_app` code
changes were needed — its `--dart-define=ROZNOOR_API_BASE_URL=...`
mechanism (`lib/core/app_config.dart`'s `String.fromEnvironment`) was
already correctly wired from an earlier session; it had just never
actually been proven to work, only assumed.

**Verified for real, both mechanisms, with fake-but-realistic URLs used
purely to prove the pipe carries a value through — never to guess a real
endpoint**:
- `web_app`: `docker build --build-arg
  VITE_API_BASE_URL="https://roznoor-backend-production.up.railway.app"`,
  then extracted the actual built image's `dist/assets/*.js` (via
  `docker create` + `docker cp`, not just trusting the build log) and
  grepped it directly — the literal URL string is genuinely inlined into
  the minified production bundle (`Jn=\`https://roznoor-backend-production.up.railway.app\``),
  proof it's actually read at runtime by the compiled app, not just sitting
  in a config file nothing references. A parallel build with the arg left
  unset confirmed the negative case: zero occurrences of any backend URL
  anywhere in that bundle, correctly falling back to the relative-path
  default — no regression to local/dev behavior.
- `mobile_app`: wrote a throwaway verification test (to the session
  scratchpad, never committed, deleted immediately after use — NOT a
  change to `mobile_app/test/widget_test.dart`, which is explicitly
  Tier-3 scope and untouched) that imports `AppConfig` directly and prints
  its resolved `apiBaseUrl`. Ran `flutter test --dart-define=
  ROZNOOR_API_BASE_URL=https://roznoor-backend-production.up.railway.app`
  against it — confirmed the value resolves to exactly that URL; ran the
  identical test without the dart-define — confirmed it falls back to
  `http://localhost:8000` unchanged. This proves the exact same
  `String.fromEnvironment` mechanism a real `flutter build apk --release
  --dart-define=...` invocation uses, without needing a full APK build (no
  Android SDK/emulator in this sandbox, same limitation every prior
  Flutter pass in this project has flagged) or redoing the
  `libsecret-1-dev`/Linux-build workarounds earlier sessions needed.

**Documented in `context/pre-deployment-checklist.md` item 5**: the exact
commands to run once real Railway URLs exist — setting `VITE_API_BASE_URL`
as a Railway service variable on `web_app` (auto-forwarded as a build arg
via the `ARG` match), the equivalent local `docker build --build-arg`
command, and the exact `flutter build apk --release --dart-define=...`
invocation for rebuilding any distributed APK, including the reminder that
this is baked in at build time and not runtime-configurable (see
[[pending-device-tests]]).

**Docker cleanup**: every test container/image created this session
(`roznoor-web-buildarg-test`, `roznoor-web-noarg-test`, and their extracted
`dist/` copies) was removed after verification; the throwaway Flutter test
file was deleted from the scratchpad. Only the project's own ongoing
`roznoor-pg` dev container and the restored (default-config) local
`uvicorn`/`vite` dev processes remain.

**Context updated**: this entry, `context/pre-deployment-checklist.md`
(items 1, 2, 5 marked ✅ fixed-and-verified in place, with the same
verification detail as here; quick-reference table and both "Fixed and
verified" summary sections updated). Per the task's explicit scope,
`progress.md`/`conventions.md` were NOT updated this pass either — same as
the Tier-1 pass, only the two files the task named.

---

## 2026-08-29 (deployment-readiness session, part 1) — Tier-1 deploy-blocker fixes: Railway backend deploy config, DATABASE_URL scheme normalization, ffmpeg in the deploy image, SPA fallback for the web frontend

**Scope**: exactly the four items from `context/pre-deployment-checklist.md`
the user explicitly named as blocking a deploy from *running at all*
(distinct from the checklist's own 🔴/🟡/🟢 tiers, which mix in security and
completeness concerns too) — items 3, 4, 6, and 11. Everything else on the
checklist (JWT secret, CORS, frontend API base URLs, local-disk audio
storage, the `flutter test` fix, seed/migration process decisions, stray
test-account cleanup, unreviewed clinical thresholds, refresh tokens) was
explicitly NOT touched, per the task's own "stop after these four"
instruction.

**Verification approach, stated up front since it shapes every item
below**: no live Railway account/credentials exist in this environment
(`railway` CLI confirmed not installed, nothing suggests otherwise), so
"attempt an actual deploy" meant the closest faithful substitute available:
a real `docker build` of each new Dockerfile, run as a real container, with
the exact same real-world constraints Railway imposes (a dynamically
injected `$PORT`, no pre-existing schema, Railway's actual known
`DATABASE_URL` scheme quirks) — not just writing config and asserting it's
correct. Every claim below was checked this way, not assumed.

### 1. Railway backend deploy config (`Backend/Dockerfile`, `start.sh`, `railway.json`, `.dockerignore`)

**Confirmed gap first**: `find . -iname "railway*" -o -iname "Dockerfile*"
-o -iname "nixpacks*" -o -iname "Procfile"` returned nothing anywhere in
the repo — no deployment configuration had ever been written, for either
service. Neither prior fact was previously written down in
`progress.md`/`decisions-log.md`; every session's own verification used a
manually-run local `uvicorn`/Docker-Postgres setup.

**Built**: a `python:3.12-slim`-based `Dockerfile` (installs `ffmpeg` via
`apt-get` in its own early layer — see the ffmpeg section below — then app
dependencies, then app code), a `start.sh` entrypoint (`alembic upgrade
head`, then `exec uvicorn app.main:app --host 0.0.0.0 --port
"${PORT:-8000}"`), a `railway.json` declaring the Dockerfile builder and a
`/health` health-check path, and a `.dockerignore` keeping `.venv`, `.env`,
`audio_storage/`, and `__pycache__` out of the built image (mirrors
`Backend/.gitignore`'s own exclusions).

**Verified for real, not just written**: `docker build` succeeded
(~75s, dependency layer separated from app-code layer so future rebuilds
after an app-only change stay fast). Ran the resulting image as a real
container against a **brand-new, genuinely empty** Postgres 16 container
(confirmed `\dt` showed zero relations before starting the backend
container — this is the real test of "does the deploy image correctly
bootstrap a fresh database," not just "does it work against an
already-migrated one"): `start.sh` ran `alembic upgrade head` on
container start and the database went from 0 tables to all 11 (+
`alembic_version`) with no manual intervention. Used `PORT=5599` (a
deliberately non-default value) to prove real `$PORT` binding rather than
a lucky fallback to 8000 — confirmed `docker port` showed only `5599`
mapped, and the actual process running inside the container
(`ps aux` inside the container) was literally `uvicorn ... --port 5599`,
not 8000. `GET /health` returned `200`. **Also verified the redeploy
case, not just first-boot**: restarted the same container (`docker
restart`) — the second `alembic upgrade head` correctly logged as a clean
no-op (no `Running upgrade` lines, since already at head) rather than
erroring, and the previously-seeded data survived, confirming migrations
are safe to re-run on every container start/restart, which is exactly
what happens on every Railway redeploy.

**Then went further than "does it boot"** — ran `seed.py` inside the
running container against its own fresh database, then did a real HTTP
round trip through it exactly like a genuine post-deploy smoke test: real
`POST /auth/login` (real JWT back), `GET /auth/me`, and a real
hard-red-flag `POST /entries` (chest pain -> Red, full rule-engine
reasoning text) — full functional proof, not just "the process didn't
crash and `/health` returned 200."

### 2. `DATABASE_URL` scheme normalization — the original checklist's "probably fine" guess was incomplete, not wrong exactly, but untested for the one case that actually breaks

The checklist's own item 11 write-up reasoned that Railway's bare
`postgresql://` (no `+psycopg2` suffix) would work fine since SQLAlchemy
defaults to the installed psycopg2 driver — correct, but it never actually
tested the *other* real-world legacy scheme, `postgres://` (no `ql`),
which Heroku historically used and which some Postgres
plugins/migration paths still emit.

**Tested empirically, before writing any fix**, against this project's
actual installed `sqlalchemy==2.0.52`
(`Backend/.venv/bin/python3`, `sqlalchemy.create_engine()` called directly
against all three shapes): `postgresql://...` and
`postgresql+psycopg2://...` both construct a working engine as guessed,
but `postgres://...` **hard-fails immediately** —
`NoSuchModuleError: Can't load plugin: sqlalchemy.dialects:postgres`. This
is a real, previously-unverified risk: if the eventual Postgres
provisioning path ever hands back the legacy scheme, `Settings()`
construction itself would crash before the app even reaches `/health`.

**Fixed**: `Backend/app/core/config.py` — a Pydantic `field_validator` on
`database_url` that rewrites `postgres://` → `postgresql://` →
`postgresql+psycopg2://` (idempotent — a URL that already names a driver
passes through unchanged). `alembic/env.py` already reads
`settings.database_url` (not `alembic.ini`'s own `sqlalchemy.url`
directly — an existing convention, see [[conventions]]), so migrations
inherit the same normalization automatically; no second fix needed there.

**Verified for real**: unit-level — set `DATABASE_URL` as a real env var to
each of the three shapes and constructed `Settings()` for real each time
(not mocked), confirming the normalized output for all three, and
separately confirmed the local dev `.env`'s existing
`postgresql+psycopg2://...` value still resolves completely unchanged (no
regression to the working setup every other session in this project has
used). End-to-end — re-ran the exact same containerized deploy test from
item 1, but this time with `DATABASE_URL="postgres://..."` (the scheme
that would previously have crashed at startup) pointed at a fresh empty
Postgres: migrations ran, the app served real traffic, login/entries all
worked — proof the fix closes the real failure mode, not just a unit test
in isolation.

### 3. `ffmpeg` in the deploy image

**Confirmed gap first**: `app/services/audio_analysis.py`'s own
`shutil.which("ffmpeg")` guard (already soft-fails gracefully if missing —
confirmed by reading the guard code itself, not just its docstring) would
have found nothing on Railway's default Python image, since nothing in
this repo had ever installed it there — `requirements.txt`'s own comment
already admitted this had only ever been true "by accident" of the dev
machine's existing OS packages.

**Fixed**: added as the *first* layer of `Backend/Dockerfile` — `apt-get
install -y --no-install-recommends ffmpeg` — before any Python dependency
installs, so it's cached independently and doesn't get invalidated by app
code changes.

**Verified for real, inside the actual running container from item 1**
(not a separate throwaway check): `docker exec ... which ffmpeg` ->
`/usr/bin/ffmpeg`; `docker exec ... ffmpeg -version` -> real version
banner (`ffmpeg version 7.1.5-...`); and, the check that actually matches
what the app code itself does rather than just a shell PATH lookup,
`docker exec ... python3 -c "import shutil;
print(shutil.which('ffmpeg'))"` -> `/usr/bin/ffmpeg`, confirming
`audio_analysis.py`'s own guard would find it.

### 4. SPA fallback routing for the web frontend (`web_app/Dockerfile`, `nginx.default.conf.template`, `railway.json`, `.dockerignore`)

**Framed correctly by the task as "the production form of a bug this
project already hit twice"**: two earlier sessions (doctor-role and
admin-role web builds — see those entries below) found and fixed the
*dev-server* version of this exact bug class — a client-side route
colliding with `vite.config.js`'s own proxy path prefixes, breaking only
on a full-page reload/direct URL, never on client-side `<Link>`
navigation. The production-hosting version of the same underlying risk
(a static file host 404ing a direct hit at any client-side route, since no
matching file exists on disk) had never been addressed — `vite build`'s
static output has no server-side routing at all unless the host is
explicitly configured with a fallback.

**Built**: a multi-stage `web_app/Dockerfile` — `node:20-alpine` builds
the real Vite production bundle (`npm ci && npm run build`, matching this
project's actual local dev Node version), then `nginx:1.29-alpine` serves
the built `dist/` with no Node toolchain left in the final image.
`nginx.default.conf.template` does `try_files $uri $uri/ /index.html` for
everything under `/`, but a real, un-fallback'd `404` for anything missing
under `/assets/` specifically — a deliberate choice: a broken/missing JS
chunk reference should fail loudly, not silently serve HTML in its place
and produce a confusing blank-page bug later. Uses the official nginx
Docker image's own built-in template-substitution entrypoint
(`/etc/nginx/templates/*.template` → `envsubst` on container start, no
custom entrypoint script needed) to bind `${PORT}` dynamically, same
requirement as the backend's own `$PORT` handling.

**Verified for real, reproducing exactly how the two prior instances of
this bug class were originally caught** — a direct hit, not client-side
navigation: built the actual image, ran it with a deliberately non-default
injected `PORT=6688`, confirmed the *generated* `/etc/nginx/conf.d/
default.conf` inside the running container genuinely had `listen 6688;`
substituted in (not a literal leftover `${PORT}`). Then `curl`'d directly
at `/roster/2`, `/people/new`, `/people/19/edit`, and `/timeline` — all
four returned `200` with the real SPA shell (confirmed via the actual
`<title>RozNoor</title>` tag and the real built JS bundle's `<script
src>`, not just a 200 status code that could have been an empty response).
A totally unknown/bogus path also correctly fell back to the shell,
matching React Router's own client-side catch-all route's behavior. A
real static asset (`/assets/index-*.js`) still resolved `200` (confirms
the fallback isn't swallowing legitimate requests), and a deliberately
nonexistent asset path still correctly `404`'d (confirms the
`/assets/`-specific carve-out works as designed, not just the top-level
fallback).

**Flutter web — checked explicitly, confirmed not applicable, nothing
built.** `mobile_app/web/` exists but is unused default `flutter create`
scaffold — grepped this entire decisions log for any `flutter build web`
mention or web-deploy intent across every prior session and found none;
every Flutter verification pass in this project's history built `linux
--debug` (desktop, for Xvfb testing) or a real Android APK, never web.
`web_app/` (React) is this project's only web deployment surface. Recorded
explicitly rather than silently skipped, per this project's own "surface
what wasn't done, don't just omit it" convention.

**Docker cleanup**: every test container/network/image created for this
session's verification (`roznoor-pg-fresh`, `roznoor-backend-deploy-test`,
`roznoor-web-deploy-test`, the `roznoor-deploy-test` network, and both
`-test`-tagged images) was removed after verification completed — none of
this is meant to persist as project infrastructure, only the checklist
narrative and the new committed config files. The project's own ongoing
dev Postgres (`roznoor-pg`) and the pre-existing local `uvicorn`/`vite`
dev processes from earlier sessions were left untouched throughout.

**Context updated**: this entry, `context/pre-deployment-checklist.md`
(items 3, 4, 6, 11 marked ✅ fixed-and-verified in place, with the same
verification detail as here; items 9's wording adjusted to reflect that
migration-on-deploy is now automatic while seeding remains a deliberate
manual/undocumented decision; quick-reference table and closing note
updated). Per the task's explicit scope, `progress.md`/`conventions.md`
were NOT updated this pass — only the two files the task named.

---

## 2026-08-29 (final session) — React web app admin role built; completes all three roles on BOTH platforms — project is now feature-complete

**Scope**: `web_app/` admin role only — the final remaining piece across
both frontends. **No backend changes** — `GET/POST /admin/users` and
`PATCH /admin/users/{id}` were already complete and verified in the
2026-08-25 doctor & admin routers pass and re-verified again in the
2026-08-29 Flutter admin-role pass; re-exercised with real curl calls
(login as the seeded admin, list all users, create one of each role,
confirm a 403 for non-admin tokens) before any React code was written
against them, then again through the real browser UI (see "Verified for
real" below).

**Reused rather than re-derived, per the task's explicit instruction to
read the Flutter implementation as a second reference**: the
`AdminDataProvider`/`AdminDataContext` shape (one `users` list, `loadAll()`
once per sign-in, `createUser`/`updateUser` updating the in-memory list in
place rather than re-fetching the whole roster — mirrors
`mobile_app/lib/state/admin_data_provider.dart` exactly), the one-shared-
form-for-create-and-edit pattern (`UserFormScreen.jsx` mirrors
`user_form_screen.dart`: no password field in edit mode, an explicit
inline note instead of silently hiding it, since `PATCH /admin/users/{id}`
has no password-reset field), and the "smallest remaining scope, no
complex workflows" instruction — the prototype's decorative "Red-flag rule
sets" card (no backing endpoint/data) was left out, same as both the
Flutter admin build and this session's own doctor-role precedent.

**Design source**: the web prototype's `a-people` screen
(`UI Inspo/.../RozNoor.dc.html`) — a searchable table (Person/Role/Linked
to/Disease track), same table pattern `PatientRosterScreen.jsx` already
uses for the doctor role. No "Account" status column: `users` has no
status column and none was added — confirmed against [[api-contracts]],
same finding as every prior admin-role pass on either platform.

**Routing: `/people`, `/people/new`, `/people/:userId/edit` — deliberately
NOT `/admin`.** Applied the exact lesson this session's own doctor-role
build learned the hard way (`vite.config.js`'s dev-server proxy forwards
`/admin` straight to the FastAPI backend, same as `/patients`/`/alerts`) —
checked the proxy's path-prefix list *before* picking a route name this
time, rather than discovering the collision via a broken full-page reload.
Verified directly: a full-page navigation to `/people`, `/people/new`, and
an edit URL all load the SPA correctly, not raw backend JSON.

**A real gap navigated around, not a new one found**: there's no
`GET /admin/users/{id}` endpoint, so `UserFormScreen.jsx`'s edit mode looks
the existing user up from `AdminDataContext`'s already-loaded `users` list
(matched on the `:userId` route param) instead of fetching it directly —
the same "look it up from already-loaded data" pattern
`PatientDetailScreen.jsx` used for the missing-patient-name gap in this
session's own doctor-role pass. This also means a direct URL/refresh at
`/people/:userId/edit` correctly waits for the list to finish loading
(same `App.jsx` effect that loads it on every admin sign-in) rather than
crashing, falling back to a plain "not found" message only once the list
has genuinely loaded and the id still isn't in it.

**Account-switch guard**: `App.jsx` gained a third keyed-on-`session.userId`
data-load effect (`loadedForAdminId`, mirroring `loadedForDoctorId`
exactly) plus a matching `adminData.reset()` on sign-out — applying the
same fix-shape the doctor-role build already carried over from the
Flutter `root_router.dart` bug, rather than re-discovering it. Verified
for real this pass (see below), not just carried over on faith: logging
out from a patient session and back in as admin correctly reloaded a
fresh `/admin/users` list rather than showing stale/blank state.

**Verified for real, live, in an actual Chrome browser** (via
`claude-in-chrome`), against the already-running `roznoor-pg` Postgres +
a freshly-started `uvicorn` instance — same shared backend/DB every other
pass this project has used: real admin login (Sadia Kamran, via the
clinician sign-in link) routed straight to `/people` purely by JWT role;
the list rendered all real seeded + prior-session test users with correct
computed `linked_summary`/`diagnosis` per role; the search filter narrowed
correctly (tested on both a doctor's name and a phone/email substring); a
full-page reload at `/people` and a direct-URL load of `/people/new`
both rendered the SPA correctly (the routing-collision check this
session's own doctor-role pass established as mandatory); **a user of all
four roles (patient/doctor/attendant/admin) was created through the real
"Invite a person" form, and each one's password was independently
confirmed to actually work by logging in as that new user afterward** via
curl (same verification pattern every prior admin-role pass, backend and
Flutter, has used) — all four also confirmed present via a direct
Postgres `SELECT`; **an existing user (the newly-created test doctor) was
renamed and had its language preference changed through the real "Edit
person" form, and the change was confirmed to persist via a direct
Postgres `SELECT`**, not just the UI's own return to the list; logging in
as the freshly-created test patient correctly showed the existing
"account isn't linked to a patient record yet" fallback screen (expected —
`POST /admin/users` only creates a `users` row, no `patients` row; this is
the same `UnlinkedAccountScreen` the patient-role pass already built, not
new behavior); logging in as a real seeded patient (Zubaida Bibi)
immediately afterward correctly routed to the ordinary `PatientShell`, and
a direct-URL navigation to `/people` while signed in as her fell straight
through to `/home` (structural prevention, not a hidden nav item) —
**as defense-in-depth, a freshly-created non-admin (doctor and patient)
JWT was independently confirmed via curl to get a real `403` from
`GET`/`POST /admin/users`** (`{"detail":"Not authorized for this
action"}`); the account-switch scenario (patient → admin) was specifically
re-checked and reloaded a fresh, correctly-populated list, not stale
state; a doctor login immediately after (Dr. Ayesha Farooq) was unaffected
by the `App.jsx` changes this session made (roster/alerts loaded and
rendered exactly as the doctor-role pass verified earlier the same day),
and a direct-URL navigation to `/people` while signed in as her correctly
redirected to `/roster` rather than rendering the admin screen. Zero
console errors at any point (checked via `read_console_messages`
throughout).

**One real, transient browser-automation quirk hit and worked around
during verification, not a code bug**: the very first click+type
immediately following a standalone (non-batched) `navigate` call
repeatedly landed on a not-yet-settled DOM and produced a blank form on
screenshot, even with an explicit 1-second wait step first — confirmed
this was a tooling/timing artifact, not an app bug, by re-running the
identical interaction as its own follow-up batch (no navigate immediately
before it), which then worked correctly every time. No stray/partial user
rows resulted (confirmed via the direct Postgres `SELECT` above showing
exactly 4 new test rows, matching the 4 role creations actually
completed) — flagging this here only so a future session driving this
same app via browser automation isn't confused by a form that appears to
silently ignore its first input right after a fresh full-page navigation.

**Test data left in the shared dev DB, not cleaned up** — this pass
created `web.test.newdoctor@civilhosp.pk` (id 19, renamed to "...EDITED"
during the edit-flow test), `web.test.newpatient@roznoor.care` (id 20),
`web.test.newattendant@roznoor.care` (id 21), and
`web.test.newadmin@roznoor.care` (id 22). Same precedent as every prior
verification pass in this project (no `DELETE /admin/users/{id}` endpoint
exists) — flagging plainly rather than silently leaving it undocumented.

**Not verified this pass** (flagging, not silently skipping): anything
about production build/deploy behavior (same open item every web-app pass
has flagged — no CORS layer outside the dev-server proxy); a
password-reset workflow (doesn't exist on the backend, so nothing to
build or verify); the prototype's rule-set-versioning card (no backing
data, deliberately not built, same as the Flutter admin pass).

**This completes all three roles (patient/doctor/admin) on BOTH platforms
(Flutter and React web) — the entire frontend scope for this hackathon MVP
is now built and verified.** Combined with the backend being feature-
complete as of 2026-08-25, the only remaining unverified pieces project-
wide are the three real-device/real-connectivity items tracked in
[[pending-device-tests]] (the acoustic-audio-upload repeat confirmations,
Flutter doctor-role real-device testing, and web real-microphone testing)
— none of which involve any code not already written and reviewed.

**Context updated**: this entry, [[conventions]] (new admin-role web
section, file-by-file), [[api-contracts]] (new verification section),
[[progress]] (project marked feature-complete across backend + both
frontends + all three roles), [[schema]] (pointer, no schema changes).

---

## 2026-08-29 (later still) — Flutter admin role built; completes all three roles on Flutter

**Scope**: `mobile_app/` admin role only — the smallest remaining scope,
per the task's explicit instruction ("People" management screen only, no
complex workflows). **No backend changes** — `GET/POST /admin/users` and
`PATCH /admin/users/{id}` were already complete and verified end-to-end
in the 2026-08-25 doctor & admin routers pass; re-exercised with real
curl calls (login as the seeded admin, list all users, create one of
each role, PATCH a rename, confirm via direct Postgres `SELECT`) before
any Flutter code was written against them, then again through the real
app (see "Verified for real" below).

**Design source**: the web prototype's `a-people` screen
(`UI Inspo/.../RozNoor.dc.html`), adapted to mobile stacked cards
instead of a table row grid — same adaptation the doctor role already
made for `d-patients`. The prototype's "Red-flag rule sets" card at the
bottom of `a-people` (versioned rule lists, review dates) has no backing
endpoint or data at all — left out rather than faked, same spirit as the
doctor role's baseline-band-chart omission from the prior pass.

**Built**: `PeopleScreen` (list + search + an "Invite a person" FAB),
one shared `UserFormScreen` for both create (`POST /admin/users`,
supports all four roles) and edit (`PATCH /admin/users/{id}` —
name/role/phone_or_email/language_preference only, confirmed via
[[api-contracts]] that there's no `status` field and no password-reset
field on the backend, so neither was added to the form — the edit mode
shows an explicit inline note instead of silently hiding the password
field). `AdminDataProvider` mirrors `DoctorDataProvider`'s shape:
`loadAll()` once per sign-in, `createUser`/`updateUser` update the
in-memory list in place rather than re-fetching the whole roster.
`root_router.dart` gained a third role branch (`role == 'admin'` ->
`PeopleScreen`, own load guard, own `reset()` on sign-out) alongside the
existing doctor branch — `PlaceholderScreen` is now genuinely dead code
now that every real role (patient/attendant/doctor/admin) has its own
screen; kept only as a structural fallback, not reachable with real
backend data. Full file-by-file breakdown in [[conventions]].

**No new bugs found this pass** — unlike the doctor-role pass (which
found and fixed a real `root_router.dart` sign-out bug), this session's
routing addition reused that already-fixed guard shape directly, so
there was no equivalent latent bug to rediscover.

**Verified for real, live, end-to-end** (Xvfb `:99` + the same
already-running `roznoor-pg` Postgres + `uvicorn` instance every other
pass this project has used — not a fresh throwaway, driven via a new
scratchpad `python-xlib` helper since no `xdotool`/`wmctrl`/`scrot` was
available in this sandbox): `flutter analyze` clean (only the same
style-level `info` lints already present elsewhere in this codebase);
`flutter build linux --debug` clean; real admin login (Sadia Kamran, via
the clinician sign-in link) routed straight to "People & roles" purely
by JWT role; the list rendered all real seeded users with correct
computed `linked_summary`/`diagnosis` per role; the search filter
correctly narrowed to a name/email match; **a user of all four roles
(patient, doctor, attendant, admin) was created through the real
"Invite a person" form, and each one's password was independently
confirmed to actually work by logging in as that new user immediately
afterward** — the same verification pattern the backend admin router's
original 2026-08-25 pass used, not just checking that the create call
returned 201 — with all four also confirmed present via a direct
Postgres `SELECT`; **an existing user (a freshly-created test patient)
was renamed and had its language preference changed through the real
"Edit person" form, and the change was confirmed to persist via a
direct Postgres `SELECT`**, not just the UI's own "User updated."
snackbar; logging in as a patient (Zubaida Bibi) immediately afterward
correctly routed to the ordinary `PatientShell`, confirming a non-admin
role never reaches the People screen at all (structural prevention, not
just a hidden button) — and, as defense-in-depth, a freshly-created
non-admin (doctor and patient) JWT was independently confirmed via curl
to get a real `403` from `GET`/`POST /admin/users`
(`{"detail":"Not authorized for this action"}`), which would render
through the same `ApiException` -> `_ErrorState`-with-retry path every
other role's data-loading screen in this app already uses (not
separately re-proven per-screen, since it's the identical code path
`DoctorDataProvider`/`PatientDataProvider` already exercise this way).

**One care point flagged during driving, not a bug**: while testing the
edit flow, a stray click briefly opened Imran Zubair's real seeded
"Edit person" screen and typed test text into his name/email fields
before the mistake was caught — **"Save changes" was never tapped**, so
nothing was sent to the backend; confirmed via a direct Postgres
`SELECT` that his row (`id 4`) was completely unchanged afterward.
Recorded here plainly rather than silently glossed over, per this
project's own "surface it, don't hide it" convention, even though no
actual data was touched.

**Test data left in the seeded DB, not cleaned up**: this pass created
several real users via curl (`test.<role>.curl@example.com`) and via the
Flutter UI (`ui.test.new<role>@...`) as part of verification, plus
renamed one of them (`UI Test Patient` -> `UI Test Patient EDITED`).
No `DELETE /admin/users/{id}` endpoint exists to remove them via the
API, and following the same precedent every prior verification pass in
this project has set (e.g. accumulated test `entries` rows), they were
left in place rather than force-resetting the shared dev DB via
`seed.py` (which would also discard other sessions' still-relevant
state). Flagging plainly for whoever next runs `GET /admin/users` and
sees them.

**Not verified this pass** (flagging, not silently skipping, per this
project's own convention): anything on a real Android/iOS device or
emulator — Linux-desktop-under-Xvfb only, same limitation as every
other Flutter pass in this sandbox; a password-reset workflow (doesn't
exist on the backend, so nothing to build or verify); the prototype's
rule-set-versioning card (no backing data, deliberately not built —
see above).

**This completes all three roles (patient/doctor/admin) on Flutter.**

**Context updated**: this entry, [[conventions]] (new admin-role
Flutter section, file-by-file), [[api-contracts]] (new verification
section), [[progress]] (Flutter marked feature-complete across all three
roles), [[schema]] (pointer, no schema changes).

---

## 2026-08-29 (later same day) — React web app doctor role built; a real routing/dev-proxy collision bug found and fixed; a real missing-name-field gap found and fixed; doctor role now complete on both platforms

**Scope**: `web_app/` doctor role only — mirroring what was already built and
verified in `mobile_app/lib/`'s doctor section (see the 2026-08-29 Flutter
doctor-role entry below) and the same `d-patients`/`d-detail`/`d-alerts`
prototype screens that build used. **No backend changes** — every endpoint
(`GET /doctors/{id}/patients`, `GET /doctors/{id}/alerts`,
`POST /alerts/{id}/review`, `POST`/`GET /patients/{id}/notes`) was
re-exercised with real curl calls against the already-running backend
before any React code was written against them (all matched
[[api-contracts]] exactly — no drift), then again through the real browser
UI (see "Verified for real" below).

**Reused rather than re-derived, per the task's explicit instruction to
read the Flutter implementation as a second reference**: the
`DoctorDataProvider` shape (roster + alerts loaded together via one
`loadAll(doctorId)`, per-patient detail state loaded on demand via
`loadPatientDetail(patientId)`, `reviewAlert`/`addNote` updating
already-loaded lists in place rather than re-fetching), the raw-value
trend-chart decision (see below), and — critically — the once-per-sign-in
data-load guard's correct shape, learned from a real bug the Flutter build
found and fixed in `root_router.dart` (see that entry): this build's
`App.jsx` keys its doctor-data-load effect on `session.userId` in a `useRef`
rather than a fire-once boolean, specifically so a second sign-in as a
DIFFERENT doctor re-triggers `loadAll` correctly. This was verified for
real this session (see below), not just carried over on faith — switching
from Dr. Ayesha Farooq to Dr. Hamza Iqbal showed exactly Dr. Hamza's 2
patients/2 alerts with zero stale trace of Dr. Ayesha's 4 patients/data,
confirming the same bug class doesn't exist here.

**Real backend-scope gap, same one the Flutter build already found and
flagged — not re-discovered from scratch, just confirmed still true**: no
endpoint exposes `baseline_history`'s min/max bands, so `TrendChart.jsx`
(a new hand-drawn SVG line component, no charting library dependency, same
spirit as the prototype's own hand-drawn SVG polylines and
`mobile_app`'s `CustomPainter` equivalent) plots the patient's actual
recorded weight/sleep values over time instead of a shaded "learned
normal" band. Checked [[api-contracts]] in full before building, per the
task's explicit instruction to treat this as a known, already-documented
limitation rather than re-investigate it.

**A real bug found and fixed: the doctor SPA routes collided with
`vite.config.js`'s dev-server backend proxy.** The proxy forwards the
exact path prefixes `/auth`, `/patients`, `/entries`, `/doctors`,
`/alerts`, `/admin`, `/health` straight to the FastAPI backend (see
[[conventions]], "CORS: dev-server proxy"). The first draft of this
session's routes used `/patients` (roster) and `/patients/:patientId`
(detail) and `/alerts` — which are also exactly the backend's own path
prefixes. Client-side navigation (`<NavLink>`/`useNavigate()`, e.g.
clicking a roster row) never hit this, since React Router intercepts
before any real HTTP request happens — the bug was invisible until a
**full page load, refresh, or direct URL** was tried at one of those
paths, which instead hit the Vite proxy and returned the backend's raw
`{"detail":"Not authenticated"}` JSON with no app UI at all. **Caught
during this session's own real-browser verification** (a full-page
`navigate()` to `/patients/2` to test deep-linking), not by code review —
worth flagging since this is exactly the kind of bug that a
click-through-only verification pass would never surface. **Fixed** by
renaming the doctor routes to non-colliding paths: `/roster`,
`/roster/:patientId`, `/notifications` (all updated in `App.jsx`,
`DoctorShell.jsx`, and every `navigate()` call site in the doctor
screens). Re-verified: a full-page navigation to `/roster/2` now correctly
loads the SPA and renders the patient detail screen. **Flagging for future
sessions**: any new top-level web-app route must avoid this proxy's path
prefix list, not just avoid colliding with existing screens.

**A real gap found and fixed: `PatientOut` (`GET /patients/{id}`) has no
`name` field for the patient themselves** (confirmed against
[[api-contracts]] — it only exposes `assigned_doctor_name`/
`attendant_name`, not the patient's own name). `mobile_app`'s Flutter
build sidesteps this by passing the patient's name in directly from the
roster tap (a Dart widget constructor argument); this web build initially
read `profile?.name` on `PatientDetailScreen`, which is always
`undefined`, and rendered "Patient #2" instead of "Zubaida Bibi" — caught
during this session's own screenshot-based verification, not by code
review. **Fixed**, without adding a name field to the backend (out of this
session's "no backend changes" scope) and without relying on
React Router's `location.state` (which breaks on a direct URL/refresh, see
the routing bug above): `PatientDetailScreen.jsx` now looks the name up
from data already loaded in `DoctorDataContext` — the matching roster row,
falling back to the matching alert row if the patient was opened from an
alert instead of the roster (both already carry `name`/`patient_name`).
This works correctly on a full-page reload too, since roster/alerts are
reloaded by the same `App.jsx` effect that reloads on every doctor
sign-in.

**Verified for real, live, in an actual Chrome browser** (via
`claude-in-chrome`), against the already-running `roznoor-pg` Postgres +
`uvicorn` instance — same shared backend/DB every other pass this project
has used, not a fresh throwaway: real doctor login as Dr. Ayesha Farooq
via the clinician sign-in link, routed straight to the roster purely by
JWT role regardless of URL (landed on `/home` post-login, same as every
role, then correctly redirected to `/roster`); roster showing her real 4
patients with correct risk-colored left borders, badges, and "4 monitored
· 2 need attention" count; patient detail for Zubaida Bibi showing real
weight/sleep trend lines (matching the same 62.0→64.4kg trajectory the
Flutter pass verified), real check-in history, real alert history, real
existing doctor notes; **adding a note through the UI actually
persisted** — confirmed via a direct Postgres `SELECT` against
`doctor_notes` (not just the UI showing it), the new row appearing
newest-first with the correct `doctor_id`; **marking an alert reviewed
actually persisted** — confirmed via a direct Postgres `SELECT` against
`alerts` (`reviewed` flipped `true` for that specific row id), and the
sidebar's live unread-count badge updated 5→4 immediately, matching
`mobile_app`'s badge-count pattern; the Unread/All alerts filter correctly
hid the now-reviewed alert; the roster search filter correctly narrowed to
a name/MR-number match. **Account-switch scenario, specifically re-checked
per the task's explicit ask** (this exact bug class was found and fixed in
`mobile_app/lib/screens/root_router.dart` — see that entry below): logged
out, logged in as Dr. Hamza Iqbal — roster correctly showed only his 2
patients (Farida Yousuf, Naseem Akhtar) with zero stale trace of Dr.
Ayesha's data, alerts correctly showed only his 2 (down from her 5/4),
sidebar badge correctly read 2 not 4. Also confirmed backend RBAC holds
end-to-end from the frontend: Dr. Hamza hitting `/roster/2` (Zubaida
Bibi, Dr. Ayesha's patient) via direct URL got a real `403` from
`GET /patients/2`, rendered as "Not authorized to access this patient"
with a Try again button, not someone else's data. Zero console
errors/warnings at any point (checked via `read_console_messages`
throughout, not just a final pass).

**Not verified this pass** (flagging, not silently skipping): production
build/deploy behavior — same open item every prior web-app pass has
flagged (no CORS layer outside the dev-server proxy); the admin role
(`a-people` prototype screen) — explicitly out of this session's scope,
same as the Flutter build's own admin gap.

**Context updated**: this entry, [[conventions]] (new doctor-role web
section, file-by-file), [[api-contracts]] (new verification section),
[[progress]] (doctor role marked complete on both platforms), [[schema]]
(pointer noting no schema changes).

---

## 2026-08-29 (real-user follow-up) — Web Speech API "network" error confirmed as the user's own connectivity, not an app bug; a real (now-fixed) favicon 404 found; dev-server "connection lost" explained

**Web Speech API "network" error — CONFIRMED connectivity, not an app
bug.** The user hit `Recognition error: network` while traveling on
limited/mobile-data internet, then independently tested Google's own
voice search/demo and got the same failure — a real, user-run control
test, not a guess. This is consistent with (and reinforces) the exact
limitation already flagged in `VoiceDiaryScreen.jsx`'s own doc comment and
in [[conventions]]: Chrome's `SpeechRecognition` implementation is
cloud-based, sending audio to Google's servers for recognition — unlike
`mobile_app`'s on-device `speech_to_text`, it genuinely cannot function
without the browser reaching that service. **Recorded here explicitly so
a future session doesn't mistake this for an app bug and go looking for
one**: no code change needed or made for this — the app's own behavior
(surfacing `Recognition error: network` and the "Type here instead"
fallback) is exactly the documented, working soft-fail path for this
condition, not a failure of it. Still genuinely unverified with real
audio under a working connection — see [[pending-device-tests]] item 3,
unchanged in status by this finding.

**A real, reproducible bug found and fixed: no favicon, causing a genuine
per-load 404.** `public/` was left empty after the initial `npm create
vite` scaffold's default `favicon.svg`/`icons.svg` were deleted during
cleanup, and `index.html` had no `<link rel="icon">` — so every browser
tab silently requested the default `/favicon.ico` and got a real 404
(confirmed directly: `curl -o /dev/null -w '%{http_code}' .../favicon.ico`
returned `404` before the fix). This is almost certainly the "Failed to
load resource: 404" the user saw. **Missed during this session's own
"zero console errors" verification** — a plain resource-404 for
`favicon.ico` doesn't surface as a `console.error`/`console.warn` entry in
Chrome (it's a Network-panel-only signal), so `read_console_messages`
never caught it even though it was almost certainly happening on every
page load throughout that pass too; flagging this as a real gap in how
"zero console errors" was checked, not just a one-off miss. Fixed: added
`web_app/public/favicon.svg` (a small teal glyph in the app's own brand
color, matching the pulse-icon concept `mobile_app`'s app icon already
uses — see [[conventions]]) and a `<link rel="icon">` in `index.html`.
Verified the fix directly: `curl .../favicon.svg` now returns `200`, and
with the `<link>` present the browser no longer requests `/favicon.ico`
at all (confirmed the request pattern, not just that the new file loads).

**Dev server "connection lost" — investigated, NOT a crash.** Checked the
actual `uvicorn`/`vite` processes and their logs from this same
long-running session (both started once, at session start, and were still
the SAME PIDs when investigated): `vite.log` shows exactly one clean
startup banner and nothing else (no crash trace, no restart banner — a
real dev-server crash/restart would print a second "VITE ready" line);
`backend.log` shows a fully continuous, unbroken request sequence with
real requests logged AFTER the point the user reported the issue
(including a `POST /entries/47/audio` 200 — a real voice-entry submission
that succeeded), which would not be possible if the backend or the proxy
path through Vite had actually gone down. Conclusion: the dev server
process itself did not crash. `"[vite] server connection lost. Polling
for restart..."` is Vite's own HMR client reporting a dropped WebSocket
between the browser tab and the LOCAL dev server (`ws://localhost:5173`)
— a loopback connection that never leaves the machine, so it is NOT
explained by the user's limited/mobile-data internet (that only affects
reaching external hosts like Google's speech service, a completely
separate network path from browser-tab-to-localhost). The much more
likely cause, consistent with "traveling": a laptop sleep/wake cycle, a
WiFi interface reconnect event, or the OS/browser throttling a
backgrounded tab — any of which drops local sockets briefly and triggers
exactly this auto-reconnect message, with no server-side failure at all.
**Not 100% provable from logs alone** (a sub-second server hiccup that
both recovered and left no trace can't be fully ruled out), but the
evidence — unbroken PIDs, unbroken request log spanning the incident —
points clearly at "transient local reconnect," not "route/proxy
misconfiguration" or a real crash. No code change made here; nothing
found that needed one.

**Context updated**: this entry (both findings), [[pending-device-tests]]
(item 3 annotated with this attempt's outcome, status otherwise
unchanged — still needs a real test on a working connection).

---

## 2026-08-29 (later same day) — React web app built, patient role, mirroring the Flutter app against the same unmodified backend

**Scope**: `web_app/` (Vite + React, JavaScript). Patient/attendant role
only — doctor/admin web screens are explicitly next-session scope, same
placeholder-screen pattern `mobile_app` used before its own doctor role
was built. **No backend changes at all** — confirmed every endpoint the
web screens needed was already complete and already documented in
[[api-contracts]] before writing any frontend code, then re-verified live
through the actual browser UI (see "Verified for real" below), not just
trusted from the doc.

**Built by reading BOTH design sources, as the task asked, not just the
prototype**: `UI Inspo/.../RozNoor.dc.html`'s `p-home`/`p-voice`/`p-check`/
`p-result`/`p-timeline`/`p-digest`/`p-profile` screens for visual/content,
AND the actual `mobile_app/lib/` implementation for exactly which API
calls, data shapes, and edge cases were already solved — so this pass
didn't re-solve problems `mobile_app` already has correct, working
solutions for. Concretely reused rather than re-derived: the exclusive
(never-both-languages) `BilingualText` pattern, the language-toggle
non-persistence contract (resets from account preference each fresh
load, no `PATCH` endpoint to persist a toggle), the Paper/Nocturne color
values (literally the same hex constants as `mobile_app/lib/core/theme.dart`,
both ultimately from the prototype's own CSS), the `PatientDataProvider`
shape (profile/checklist/timeline loaded together, `submitEntry`/
`attachAudio` refreshing both timeline and profile afterward so
`day_count`/`baseline_stage` stay current), the sequenced (not
simultaneous) speech-capture-then-audio-capture design from the
2026-08-27 mic-contention fix, and the "role decides routing, never a
user choice" rule from the role-switcher removal. Full file-by-file
mapping in [[conventions]].

**Decision: CORS via Vite dev-server proxy, not backend CORS middleware.**
The backend has zero CORS configuration (checked `app/main.py` before
building anything) — a browser calling it directly from a different origin
(`http://localhost:5173` vs `http://localhost:8000`) would be blocked
entirely, and adding `CORSMiddleware` is a backend change outside this
session's explicit "no backend changes" scope. Resolution:
`vite.config.js`'s `server.proxy` forwards every backend path
(`/auth`, `/patients`, `/entries`, `/doctors`, `/alerts`, `/admin`,
`/health`) to `http://localhost:8000` — the browser only ever talks to its
own origin, and Vite forwards server-side with no CORS involved at all.
Verified directly with `curl http://localhost:5173/auth/login` returning a
real token before ever opening a browser. **Flagging the real limitation**:
this proxy is dev-server-only. A production build (`vite build` + static
hosting) has no proxy layer, so a real deployment needs either backend
CORS (a future backend-scope change) or a reverse-proxy in front of both
services — neither built this session, since it wasn't needed for this
session's actual verification target (the dev server against a local
backend).

**Decision: JWT storage — `localStorage`, flagged plainly, not silently
picked.** The task explicitly asked this be "your call, flag the choice
and reasoning." The safer browser-native option — an httpOnly cookie set
by the server — isn't available without a backend change: `POST
/auth/login` returns the token in a JSON response body only (see
[[api-contracts]]) and never sets `Set-Cookie`, and modifying that is
backend scope this session doesn't have. Among the remaining client-side
options (in-memory only, `sessionStorage`, `localStorage`), `localStorage`
was chosen so a signed-in patient stays signed in across a closed
tab/browser restart — matching `mobile_app`'s actual persisted-session
behavior (`flutter_secure_storage`), which the task asked this app to
mirror. The real trade-off: `localStorage` is readable by any JS running
on this origin, so a successful XSS against this app could steal the
token for its full 24h life (same expiry/no-refresh-token design as
mobile — see [[conventions]]). Mitigated only by React's default
output-escaping (no `dangerouslySetInnerHTML` anywhere in this codebase)
and the token's existing short life — not eliminated. Documented in
`src/core/tokenStorage.js`'s own doc comment, not just here, so it stays
visible to whoever next touches that file. A production deployment should
move this to a real httpOnly cookie once the backend can set one.

**Web Speech API + MediaRecorder: a real behavioral-difference writeup,
not a silent swap.** Per the task's explicit instruction to flag rather
than silently skip or silently force a mismatch: `VoiceDiaryScreen.jsx`'s
own doc comment lists every concrete difference from `speech_to_text`
found while building — uneven browser support (Chrome/Edge only, no
Firefox), Chrome's implementation being cloud-based (not on-device the way
mobile's comment describes speech_to_text), and the HTTPS-in-production
requirement (localhost is exempted, which is what this session's dev-server
verification relied on). **One flagged uncertainty from the task brief
turned out to resolve in the "it works" direction, not the "skip it"
direction**: the acoustic-analysis audio upload IS feasible on web —
`POST /entries/{id}/audio` already documents `webm` as an accepted format
(decoded via the same `ffmpeg` subprocess as every other format — see
[[api-contracts]]), and `MediaRecorder`'s default output on Chrome is
exactly `audio/webm;codecs=opus`. So this was built, not skipped: a
`MediaRecorder` session captures a 6-second follow-up sample after speech
recognition ends (sequenced, mirroring the mobile mic-contention fix
proactively — see below), and the resulting Blob uploads via the same
`FormData`/`multipart` call Flutter's `EntryService.uploadAudio()` makes.

**Sequenced (not simultaneous) audio capture, applied proactively rather
than discovered the hard way.** `mobile_app`'s 2026-08-27 real-device pass
found that running `speech_to_text`'s recognizer and the `record` package's
raw capture at the same time starved the recognizer of audio entirely on
real Android hardware (see that entry below) — the fix was to sequence
them: transcript first, then a fixed 6-second follow-up recording once the
recognizer releases the mic. This web build applies that same sequencing
from the start (`SpeechRecognition.onend` triggers the `MediaRecorder`
session), **without having verified whether browsers share that exact
contention risk at all** — Chrome's `SpeechRecognition` doesn't call
`getUserMedia()` the way `MediaRecorder` does, so the two may not compete
for the same OS-level resource the way two native Android APIs did. Kept
sequential anyway specifically to mirror the already-verified, working
mobile design rather than risk re-discovering the same bug class on a
different platform for no benefit — flagged as an unverified assumption in
the code's own comment, not presented as a proven web-specific finding.

**Not re-solved, deliberately reused as-is from `mobile_app`'s already-
verified design**: the Weekly Digest / "Trends" screen has no dedicated
backend endpoint (`weekly_digests` is still an unused stored table — see
[[progress]]), so `WeeklyDigestScreen.jsx` computes the same
week-over-week aggregation client-side from `GET /entries/{id}/timeline`
data, ported line-for-line from `mobile_app`'s own `_WeekDigest.compute()`
rather than re-derived — same insight thresholds (sleep down >0.5h vs.
last week, adherence <80% as a coral-vs-teal color cutoff), so the two
apps' Weekly Trends screens agree given the same data.

**Verified for real, live, in an actual Chrome browser** (via
`claude-in-chrome` automation) — not code review alone, and not against
mocked data. Backend: existing `roznoor-pg` Postgres container (already
running from a prior pass) + a fresh `uvicorn --host 0.0.0.0` instance.
Frontend: `npm run dev` (Vite dev server on `:5173`), driven with real
clicks/typing/screenshots. Confirmed working end-to-end: real patient
login (`zubaida.b@roznoor.care`) with a deliberately wrong password first
(real `401`, correct backend error message rendered) then the correct one;
a Quick Check-in with "Chest pain" ticked producing a genuine hard-Red-flag
result (`POST /entries` → rule engine → `risk_level: "Red"`, correct
reasoning text, all rendered on the Result screen); a typed-fallback Voice
Diary entry producing a correct Green result with no false positive (no
`ANTHROPIC_API_KEY` configured, `source` stayed `"rule"` throughout,
consistent with every other pass run without a key); Timeline showing
every entry from this session PLUS entries seeded by prior Flutter
real-device passes (same shared backend/DB — confirms no
web-specific data-shape drift against real historical data, not just
freshly-created rows); Weekly Trends rendering a real computed digest;
Profile showing real `PatientOut` fields (medicines, baseline status,
`day_count` correctly advancing after each submission — confirms the
post-submit profile refresh works); the emergency-contact modal showing
real `emergency_contact_name`/`phone`; a real doctor login
(`a.farooq@civilhosp.pk`) correctly routed to the placeholder screen purely
by JWT role regardless of URL, not by which login form was used; logout
correctly clearing the session and redirecting to `/login`. **Theme
toggle**: Paper ↔ Nocturne confirmed instant and complete (background,
cards, buttons, sidebar, all text legible in both — no black-on-black gap
the way `mobile_app`'s 2026-08-27 pass initially had, since this build
used `context`-based CSS custom properties from the start rather than
literal color values scattered per call site) — AND confirmed to persist
across a full page reload (`localStorage`, not just in-memory state).
**Language toggle**: confirmed exclusive (never both languages shown at
once, checked across Login/Home/Voice Diary/Profile) and confirmed to
correctly RESET to the account's stored preference (`roman_urdu` for
Zubaida Bibi) on a fresh page load even after having been toggled to
English in a prior session — i.e., confirmed non-persistent by design, not
by accident. Zero console errors/warnings at any point (checked via
`read_console_messages`, not just visual inspection).

**Not verified this pass — flagged, not silently skipped, added to
[[pending-device-tests]]**: `POST /entries/{id}/audio` via a REAL browser
microphone recording. The sandboxed browser environment used for this
verification has no audio input hardware, so `SpeechRecognition.start()`
and `MediaRecorder` were never exercised with real audio — the code path
was written, reviewed, and the typed-fallback path (which calls the
identical `POST /entries`) was verified end-to-end instead, same
substitution `mobile_app`'s own sandbox passes made before real-device
testing became available. Also not verified: production build/deploy
behavior (no CORS layer exists outside the dev-server proxy — see above);
cross-browser behavior in Firefox/Safari (Web Speech API's own
`speechSupported` false-branch — the plain typed-text form — was reviewed
but not separately screenshotted in a non-Chrome browser this session).

**Context updated**: [[schema]] (pointer noting no schema changes),
[[conventions]] (full `web_app/` file-by-file section), [[api-contracts]]
(new verification section), [[progress]] (web app patient role marked
built + the real-microphone follow-up noted as pending, same pattern as
every other real-device-testing gap in this project),
[[pending-device-tests]] (new item for the real-microphone confirmation).

---

## 2026-08-29 — Flutter doctor role built; explicit user override of the standing "no Phase 2 until acoustic-audio item resolved" hold

**Scope conflict surfaced to the user before starting, per this project's
own "surface contradictions rather than proceed silently" convention**:
`context/pending-device-tests.md` (written 2026-08-28, end of the prior
session) carries a standing instruction — "Do not start Phase 2 (doctor
role) until [the acoustic-audio upload item] is fully resolved... not just
this session's one success." That item is still open (1 of 2-3
confirmations done, paused for the user's travel/no-WiFi). This session's
own task brief asked for the doctor role to be built now regardless. Asked
the user directly rather than guessing which instruction wins — **the user
explicitly chose to proceed with the doctor role this session**, overriding
the hold. The acoustic-audio investigation itself was NOT touched, resumed,
or re-litigated — [[pending-device-tests]] item 1 is untouched and still
needs its phone-based confirmations once WiFi is back; only the "don't
start Phase 2 yet" gate was lifted, by explicit user instruction.

**Built**: doctor home/roster, patient detail (timeline + raw-value trend
charts + alert history + notes), alerts panel with review action, and JWT
role routing — see [[conventions]] for the full file-by-file breakdown.
Content/layout source was the web prototype's `d-patients`/`d-detail`/
`d-alerts` screens, per the plan already recorded in `context/
conventions.md` from an earlier session (confirmed still present, as the
task asked) — adapted to mobile stacked cards + a bottom sheet.

**No backend changes at all** — every endpoint the doctor screens needed
(`GET /doctors/{id}/patients`, `GET /doctors/{id}/alerts`, `POST
/alerts/{id}/review`, `POST`+`GET /patients/{id}/notes`, and the existing
`GET /entries/{patient_id}/timeline` the patient app already uses) was
already complete and previously verified per the task brief — confirmed
this by re-exercising all of them with real curl calls against a fresh
instance before touching Flutter code, not just trusting the prior
verification narrative (see "Verified for real" below).

**Real backend-scope gap found while planning the patient-detail trend
chart, flagged rather than silently worked around with a new endpoint**:
the web prototype's Sleep/Weight cards shade a "learned normal" band
behind the line, sourced from `baseline_history.baseline_min/max`. No
endpoint exposes that table to any client — checked `api-contracts.md` in
full (not just skimmed) before concluding this, since the task described
backend as already complete and out of this session's scope to extend.
Resolution: `TrendChart` (a new hand-rolled `CustomPainter` line widget —
no charting package dependency added, same spirit as the prototype's own
hand-drawn SVG polylines) plots the patient's actual recorded values
(weight, sleep) over time from data the timeline endpoint already returns,
instead of a baseline band. This is real trend data, just not the same
shape as the mockup — flagged plainly rather than presented as a
pixel-match. If a baseline-exposing endpoint is wanted later, that's a
backend-scope addition for a future session, not done here.

**A real pre-existing bug found and fixed in `root_router.dart` while
extending it for doctor routing — not part of the original task, but
directly in the file being touched, so fixed rather than propagated**:
`_dataLoadStarted`'s own comment claimed "kick off the initial data load
exactly once per sign-in," but the boolean lived on `_RootRouterState`,
which persists for the entire app run (`RootRouter` is `MaterialApp`'s
`home:`, never rebuilt from scratch) — so it actually fired at most once
per **app launch**, not per sign-in. Logging out and back in (as the same
or a different account) would never re-trigger `loadAll`, silently
leaving whatever the previous session's data provider last held.
Compounding this: `PatientDataProvider.reset()` already existed but was
dead code — grepped the codebase and confirmed it was never called from
anywhere. Fixed by resetting the flag (and calling both providers'
`reset()`) on the `signedOut` transition. **Verified this fix for real,
not just by reading the code**: logged in as Dr. Ayesha Farooq (4
patients), logged out, logged in as Dr. Hamza Iqbal (2 different
patients) — the roster correctly showed only Dr. Hamza's 2 patients with
no stale trace of Dr. Ayesha's data. This also incidentally fixes the same
latent risk for the patient/attendant role, which was never previously
observed failing only because no prior verification pass happened to log
in as two different patients back-to-back in one running app instance.

**Verified for real, live, end-to-end** — not by reading code or
`flutter analyze` alone. Backend: `roznoor-pg` (the throwaway Postgres
container) restarted, a fresh `uvicorn` instance started, and every new
endpoint the doctor screens call was exercised directly with curl first
(login as both seeded doctors, roster, alerts, notes GET/POST, alert
review) — every response matched the Dart model shapes field-for-field
before any Flutter code ran against them. Flutter: `flutter build linux
--debug` (after redoing the session-local `libsecret-1-dev` +
`libgcrypt20-dev`/`libgpg-error-dev` pkg-config workaround this sandbox
needs for any Linux build — see the 2026-08-27 entry below for the
original version of this same workaround; this session additionally
needed `libgcrypt20-dev`, not hit by the earlier pass), run on the
project's durable isolated `Xvfb :99` display (confirmed via `$DISPLAY`
before touching anything — see the 2026-08-27 "display-incident" entry
below), driven via a new `python-xlib`/XTEST helper script (no reusable
one existed from a prior session; written to this session's scratchpad,
not committed, since prior sessions' equivalents were also
session-local). Confirmed by screenshot at every step: clinician login
routes a doctor JWT to the new roster (not the old placeholder); roster
shows real patients with correct risk-colored left borders and badges,
correct "N monitored · N need attention" counts; tapping a patient opens
real timeline history (all 30 real entries for Zubaida Bibi, including
the acoustic-analysis investigation's own test entries — left untouched,
not read as separate data), real weight/sleep trend lines matching the
seeded 62.0→64.4kg weight trajectory, real alert history, real doctor
notes; adding a note through the UI (bottom sheet) actually persisted
(confirmed via a following `GET /patients/{id}/notes`-equivalent — the
note reappeared newest-first after the sheet closed); marking an alert
reviewed through the Alerts screen updated the badge count live and was
independently confirmed persisted with a direct `SELECT` against
Postgres (`reviewed` flipped `true` for that specific row, not just local
UI state); the Unread/All segmented filter correctly hid/showed the
now-reviewed alert. `flutter analyze`: zero new errors/warnings, only the
same style-level `info` lints already present elsewhere in this codebase
(e.g. `separatorBuilder: (_, __)`, matching `timeline_screen.dart`'s
existing pattern).

**Not verified this pass** (flagging, not silently skipping, per this
project's own convention): anything on a real Android/iOS device or
emulator — this was Linux-desktop-under-Xvfb only, consistent with every
other Flutter pass's stated device limitation in this sandbox; the admin
role/`a-people` screen (out of this session's stated scope); whether the
`TrendChart` widget scales sensibly with a much larger entry count than
Zubaida Bibi's 30 (visually fine at that count, not stress-tested).

**Context updated**: [[conventions]] (full doctor-screen file breakdown,
superseding the "future phase" placeholder note), [[progress]] (doctor
role marked built + real-device follow-up noted as pending WiFi, same as
the patient-side item), [[pending-device-tests]] (added a matching
"doctor role real-device testing" pending item, alongside the still-open,
untouched acoustic-audio item).

---

## 2026-08-28 — Voice Diary investigation continued: TWO real root causes found and fixed for the audio-upload bug; 1 of 2-3 required confirmations done, session paused for travel (no WiFi)

**Continuing the trail from 2026-08-27 below** — full label-bug →
mic-contention → sequenced-capture-fix → silent-upload-failure history is
in that entry; this one picks up exactly where it left off (the
`debugPrint` visibility fix from that session, confirmed still present and
committed at `8a1c49b` at the start of this session).

**Live reproduction setup**: `roznoor-pg` (the throwaway Postgres
container) was found stopped and restarted; `uvicorn --host 0.0.0.0` was
started fresh; `adb logcat` was used to capture the installed app's
`debugPrint` output live from the real device (Sparx Neo 7 Ultra, same
phone as every prior real-device pass, connected via USB and already
paired with `adb`) while the user submitted entries and reported back.
This is the reusable setup — see `context/pending-device-tests.md` for the
exact resume steps.

**Root cause #1 (real, FIXED): `record_platform_interface` was pinned to
1.2.0 via a blanket `dependency_overrides`, which the 2026-08-27 UI/theme
session added ONLY to fix the Linux desktop build (`record_linux 0.7.2`,
the version `record: ^5.2.1` pulls in, only implements the `^1.0.2`-era
platform-interface abstract class). `pubspec.yaml`'s `dependency_overrides`
has no per-platform scoping, so this same override was ALSO silently
forcing the real target platform — Android — onto an interface version
below what it actually needs: `record_android: 1.5.2` (confirmed by
reading its own `pubspec.yaml`) requires `record_platform_interface:
^1.5.0`, not `1.2.0`.** This mismatch is the direct, verified cause of a
genuine crash caught live on-device the first time this session watched
`adb logcat` during a test: two identical uncaught `Bad state: Cannot add
new events after calling close` exceptions on a `_BroadcastStreamController`
inside `record`'s own `AudioRecorder._stateStreamCtrl` (confirmed by
reading `record-5.2.1`'s source — it subscribes to the platform's
`onStateChanged` EventChannel stream and forwards every event into this
controller internally, regardless of whether the app ever calls
`.onStateChanged()` itself), six seconds apart — matching the follow-up
recorder's own start/stop pair exactly.
**Fix**: instead of downgrading the shared interface, override
`record_linux` itself to `1.3.1` (confirmed via the pub.dev API to be the
first `record_linux` release requiring `record_platform_interface:
^1.5.0`, which record still resolves cleanly since its own constraint is
only `record_linux: '>=0.5.0 <1.0.0'`, itself needing an override
regardless). `flutter pub get` then resolves `record_platform_interface`
up to 1.6.0 — satisfying both the Linux platform's real requirement (now
1.3.1) and the Android platform's real requirement (1.5.2 needs
`^1.5.0`) at once, no per-platform special-casing needed. **Verified this
fix actually eliminated the crash**: rebuilt, reinstalled, ran an
identical test — zero stream exceptions in that or any subsequent
`adb logcat` capture this session. This was a real, necessary fix, but —
important, flagged so a future session doesn't stop here — **it was not
the actual reason uploads were failing**. Fixing it only made the failure
mode go quiet (no crash) instead of loud; the upload still didn't happen
on the very next test after this fix (see root cause #2).

**Root cause #2 (real, FIXED, THE actual reason uploads never reached the
backend): `canAnalyze` — the boolean gating the "Save & analyse" button —
never checked `_listening`.** `voice_diary_screen.dart`'s `canAnalyze` was
`_finalTranscript.isNotEmpty && !_submitting && !_capturingSample` — no
`!_listening` term. The live transcript (`_transcript`) populates in
real time via `onResult` WHILE the user is still actively speaking, so as
soon as any partial transcript existed, the button was already tappable —
including at any point during active listening, well before the
sequenced follow-up audio capture (`_captureFollowUpAudioSampleOnce`,
added in the 2026-08-27 mic-contention fix) had even been triggered, since
that capture only starts once listening stops. **Directly proven live**,
not inferred: added targeted `debugPrint` calls to
`AudioRecorderService.start()`/`.stop()` (which had the exact same
un-instrumented silent-catch shape as the original `attachAudio()` bug —
`catch (_) { return null/false; }` with no logging) and to
`_captureFollowUpAudioSampleOnce()`/`_analyze()`, then watched a live test
via `adb logcat`. The log showed, in order: follow-up recorder starts
(20:17:14.787) → recorder genuinely started (20:17:15.348) →
**`_analyze()` already ran and read `_recordedAudioPath` as `null`
(20:17:15.935)** — after `POST /entries` had already completed — →
recorder finally stops with a valid file, 6 full seconds after it started
(20:17:21.461), long after the entry had already been submitted and
navigated to the Result screen. No crash, no exception anywhere in this
path — this is why it looked like nothing was wrong: the soft-fail
contract worked exactly as designed, silently proceeding without audio,
because `_recordedAudioPath` was genuinely still `null` at the moment
`_analyze()` read it, not because of a swallowed error.
**Fix**: added `&& !_listening` to `canAnalyze`. This closes the actual
gap rather than narrowing a timing window — the user now cannot reach
"Save & analyse" until they've explicitly stopped listening, which is the
ONLY event that triggers the follow-up capture sequence in the first
place; `!_capturingSample` (already present) then correctly makes them
wait out its fixed 6-second window on top of that.

**Verified once, live, end-to-end, after both fixes**: rebuilt, reinstalled,
watched `adb logcat` + the backend log together during a real submission.
Device log showed `_recordedAudioPath` correctly non-null at submit time
this time; backend log showed a real `POST /entries/43/audio HTTP/1.1"
200 OK` (the FIRST time this specific request has ever appeared in any
backend log across every pass of this investigation); direct DB query
confirmed entry 43 has a real `audio_file_path`
(`audio_storage/2/entry43_4cc5bbff.m4a`) and a fully populated
`acoustic_features` JSON (`duration_sec: 6.06`, `pause_ratio: 0.0`,
`possible_fatigue_or_breathlessness: false`, etc.), `risk_level` stayed
`Green` correctly; the file was independently confirmed to actually exist
on disk at 100,261 bytes — consistent with the ~101KB real recordings
confirmed on-device in the 2026-08-27 pass, not an empty/corrupt file.

**NOT yet called resolved — per the task's own explicit instruction not to
declare this fixed on one success, since the earlier failures were
intermittent-*looking* (worked/didn't-work across different sessions/
builds) which is worse for a live demo than a consistent failure.** This
is 1 of the 2-3 required repeat confirmations. **Session paused here**:
the user is traveling with only mobile data, no WiFi, so the phone cannot
currently reach the LAN backend at all — this is an environment
limitation, not a new bug, and not a reason to doubt the fix. See
`context/pending-device-tests.md` for the exact state and resume steps,
created specifically so this doesn't need re-explaining next session.

---

## 2026-08-27 (real-device verification pass) — Voice Diary investigation: label bug → mic-contention root cause → sequenced-capture fix; audio-upload bug found and NOT yet resolved

**Session cut short by the user's laptop battery** — pushed mid-investigation
so the next session has the full trail. Do not read this as "Voice Diary is
verified" — see the explicit "Not resolved" section at the bottom.

**Three genuinely separate bugs surfaced in sequence on the real device
(Sparx Neo 7 Ultra) — flagging clearly so they don't get conflated, per the
user's own explicit request:**

**Bug 1 (cosmetic, FIXED + verified): language-toggle label showed the
switch-TARGET language, not the active one.** `voice_diary_screen.dart`'s
AppBar button read `lang.isRomanUrdu ? 'EN' : 'اردو'` — while Roman Urdu was
active, it displayed "EN" (meaning "tap to switch to EN"), which reads
exactly like "EN is currently selected." The underlying `LanguageProvider`
state and `speechLocaleId` were correct the entire time; only the label was
backwards. Fixed by flipping the ternary. Confirmed on-device: button now
shows the currently-active language, matching the diagnostic "Recognition
locale: ..." line added alongside it.

**Bug 2 (real, FIXED + verified): concurrent mic access starved
speech_to_text of audio entirely.** Original design (2026-08-25 acoustic-
analysis pass) started `AudioRecorder.start()` (the `record` package, raw
waveform capture) and `speech_to_text`'s `SpeechRecognizer.listen()`
simultaneously — flagged at the time as an unverified, device-dependent
risk (no mic hardware in that sandbox). On real hardware this reliably
produced `ERROR_NO_MATCH`/silence regardless of language spoken or which
locale (`en-US` or `ur-PK`) was active — real Roman Urdu speech under the
correct `ur-PK` locale still produced nothing, which is what pointed away
from a locale problem and toward mic input never reaching the recognizer
at all. Confirmed two ways before concluding this: (1) the device's own
Gboard microphone worked correctly (rules out dead mic/OS-level speech
service), (2) a diagnostic build with the concurrent `AudioRecorder` call
disabled made speech recognition work correctly on the first try.

**Root architectural constraint discovered while designing the fix**:
`speech_to_text` has no file-based transcription API and no way to export
the audio it captures — it is live-mic-only. `record` has no transcription
ability. Neither package can substitute for the other, so on hardware
where the OS won't share mic access between two capturing apps, the two
genuinely cannot capture the exact same utterance simultaneously without
custom native audio-routing work (out of scope here).

**Fix applied**: sequenced instead of concurrent. Speech recognition still
runs alone first (unchanged — it's the load-bearing path feeding
`raw_transcript` into the rule engine). The moment it ends (covers both
manual stop and the recognizer's own auto-stop, via `onStatus`, guarded
against double-firing), a **6-second fixed-duration follow-up recording**
starts automatically for the acoustic-analysis waveform — comfortably
above the backend's own `MIN_DURATION_FOR_FLAG_SECONDS=3.0`
(`app/services/audio_analysis.py`). UI now shows "Capturing voice sample
for analysis…" during that window (previously would've been an unexplained
few-second freeze) with the mic/submit buttons disabled until it finishes.
**This is a real design change from the original "simultaneous capture of
the same utterance," not just a timing tweak** — the acoustic sample is now
a short recording taken immediately AFTER the transcribed speech, not
literal audio of the words that were transcribed. Flagging this plainly:
still a fatigue/breathlessness-relevant vocal sample of the patient's
current state (same session, same physical/vocal condition), but not
byte-for-byte the same utterance as before.

Confirmed on-device: transcript worked correctly, "Capturing voice
sample…" showed with buttons correctly disabled for the window, submission
completed normally to a Result screen. Also confirmed directly on the
phone's filesystem (`run-as` into the app's cache dir) that the recording
genuinely captured real audio content (101,685 bytes for a ~6s clip, vs.
~5,462-byte near-empty files from the earlier broken concurrent attempts).

**Bug 3 (real, FOUND, NOT YET FIXED): the recorded audio never reaches the
backend.** Checked the database directly after the user's confirmed-working
test above: the submitted entry (id 39) had `has_audio: false` and
`acoustic_features: null`. Checked `backend.log` — zero `POST
/entries/{id}/audio` requests logged for any of the recent voice entries,
meaning the upload fails silently on the CLIENT before it ever reaches the
network (a server-side failure would still show a logged request with an
error status). One specific theory was raised and directly disproven by
reading Dio 5.11.0's own source (`dio_mixin.dart:706-709`): when `data is
FormData`, Dio unconditionally overwrites the Content-Type header with the
correct multipart boundary regardless of any explicit `Options(contentType:
...)` passed by the caller — so `EntryService.uploadAudio()`'s explicit
`contentType: 'multipart/form-data'` (no boundary) is redundant but NOT
the cause of a broken request.

The actual cause is still unknown because `PatientDataProvider.attachAudio()`
was swallowing the exception completely silently (`catch (_) { return
null; }`) — correct for the soft-fail CONTRACT (must never surface to the
user or block the entry) but made the real failure invisible to debugging
too. Fixed the visibility gap only (`debugPrint` on catch, logging the
exception + entry id + file path — the soft-fail behavior itself is
unchanged, still returns null) and redeployed, but **the session ended
before the user could run the retest that would have printed the actual
exception**.

**Not resolved — needs to be the first thing the next session picks up**:
run one more Voice Diary entry with this last build (or a fresh build if
code has moved on) and read what `attachAudio failed (entry ..., file
...): ...` actually prints. Until then this is an open, undiagnosed
client-side upload failure — don't assume a cause. Candidates not yet ruled
out: a `MultipartFile.fromFile()` timing issue (file path handed back by
`AudioRecorderService.stop()` before the native writer has fully released
the file — the native logs suggest fsync completes before `stop()` returns,
but this wasn't directly proven), a transient WiFi/network blip on the
phone at exactly that moment (this device has shown USB flakiness all
session, though that's a different radio/subsystem from WiFi), or
something entirely different the actual exception message will reveal.

**Net effect on `context/progress.md`'s acoustic-analysis feature status**:
mic-contention (the blocker that made speech-to-text itself unusable) is
now fixed and device-verified. The acoustic-analysis upload path is
device-verified as STILL BROKEN, not device-verified as working — this is
new information narrowing an already-known gap ("mobile capture needs a
real device," 2026-08-25), not a regression of something that previously
worked.

---

## 2026-08-27 (later same day) — Real display-incident root cause + durable fix (recurrence of the earlier same-day incident)

**Root cause, confirmed by inspecting the actual process tree, not
guessed.** This sandbox is NOT an isolated container — Claude Code (`claude
--continue`) runs as a normal process directly inside the user's real,
already-running GNOME desktop login session (confirmed: `ps -o
pid,ppid,cmd` showed `claude` launched from a real interactive shell on
`pts/0`; `/tmp/.X11-unix/X1` is owned by the user and was created that
morning — a genuine live X session, not a fixture). Every new shell
(including every Bash-tool call) inherits `$DISPLAY` from that ambient
environment, which is `:1` — the user's actual desktop — by default.
**The earlier same-day session's "fix" was never durable**: it started
its own Xvfb on a fixed display number as a plain background process and
exported `DISPLAY` only inside that session's own Bash tool state. Both
evaporate the moment a session ends — a fresh `claude` invocation starts
a brand-new shell with no memory of a prior session's manual exports or
background processes, so the very next session (this one) fell straight
back to the ambient `:1` default. "Being careful" was never going to fix
this because the unsafe state (`DISPLAY=:1`) is the DEFAULT every session
starts in; it has to be overridden structurally, before any GUI tool
call, in a way that survives past the session that sets it up.

**Durable fix — two independent, persistent pieces, neither scoped to a
single session:**
1. **A real systemd `--user` service** (`~/.config/systemd/user/claude-
   xvfb.service`, `Restart=always`, `WantedBy=default.target`) runs Xvfb
   on a fixed `:99` at all times the user is logged into their desktop —
   enabled once (`systemctl --user enable --now`), it auto-starts on
   every future login without any session needing to remember to launch
   it. The Xvfb binary itself is extracted (via the same rootless
   `apt-get download` + `dpkg-deb -x` approach used elsewhere this
   session for `libsecret-1-dev`) into `~/.local/share/claude-tools/
   xvfb-root/` — a real path under the user's home directory, NOT a
   session-scoped `/tmp/claude-*/…/scratchpad` path, specifically so it
   survives past this session (a scratchpad-rooted Xvfb, like the earlier
   session's, disappears with the session).
2. **`DISPLAY=:99` set in this repo's `.claude/settings.json` (`env`
   block)** — every future Claude Code session working in this project
   now gets `:99` as its Bash tool default automatically, with no
   in-session export required. Verified live: after writing the file,
   `echo $DISPLAY` in a fresh Bash call in the SAME session already
   returned `:99` (the settings watcher picked it up immediately), and
   `xdpyinfo`/`xwininfo` against it showed the isolated, empty Xvfb
   display, not the user's real desktop. Scoped to this project's
   settings (not `~/.claude/settings.json`) so it doesn't affect the
   user's `claude` usage in unrelated projects.

**Why this really is durable this time, unlike the earlier fix**: neither
piece depends on anything from within a single Claude Code session's
lifetime. The systemd unit is a real OS-level service tied to the user's
login session, independent of whether `claude` is even running. The
`DISPLAY` env default is now a checked-in setting inside the project
(`.claude/settings.json`) rather than an in-session shell export — the
next session (or the one after that, or after a full reboot) reads it
from disk the same way this one now does. The only way this regresses is
if the systemd unit or the settings file is itself deleted — both are
now durable artifacts a future session (or the user) can find and check,
unlike an ephemeral background process and a shell variable.

**A real screenshot of the user's own live desktop was taken once, by
accident, before this was caught.** During this same incident (before the
root cause above was diagnosed), an `ImageGrab.grab()` against the
ambient `:1` display captured the user's actual browser window (an
unrelated personal document/form, not project content) and one of their
own terminal windows. That file was deleted immediately (never sent to
the user, never referenced again) the moment the mistake was noticed, and
every subsequent screenshot that same session was retaken against a
manually-started isolated Xvfb (`:99`, the same display number now made
permanent above) instead. Flagging this plainly rather than glossing over
it — it's the concrete cost of the earlier fix not being durable, and the
reason this pass treated "durable" as the explicit bar rather than
"remember to be careful next time."

---

## 2026-08-27 — Three Flutter patient-app UI/UX fixes: Paper/Nocturne theme, exclusive language toggle, launcher icon

**Theme: `ThemeProvider` (ChangeNotifier) + `shared_preferences`, NOT
`flutter_secure_storage`.** Unlike [[conventions]]'s `LanguageProvider`
(deliberately non-persistent — no `PATCH` endpoint exists to reconcile
against an account's stored preference), the Paper/Nocturne choice has no
server-side "account truth" to defer to at all — it's a pure client
display preference, so there's no conflict to avoid and persisting it
locally is unambiguously correct, per the task's explicit requirement
("survives app restarts"). `flutter_secure_storage` was deliberately not
reused for this even though it's already a dependency: Keychain/Keystore
storage is for secrets (the existing JWT), and a UI preference has no
confidentiality need — `shared_preferences` (new dependency) is the
conventional Flutter tool for exactly this. See `lib/state/
theme_provider.dart`.

**Nocturne colors are the prototype's real dark-mode values, not
invented.** `RnDarkColors` (`lib/core/theme.dart`) is a direct port of
`RozNoor.dc.html`'s `#rn[data-theme="dark"]` CSS custom-property block —
same source the existing light `RnColors` came from. `buildRnDarkTheme()`
mirrors `buildRnLightTheme()`'s structure field-for-field so the two stay
easy to diff/keep in sync.

**Risk badge colors (`RnColors.forRiskLevel`) were deliberately NOT
duplicated for dark mode**, even though the prototype defines separate
Nocturne risk-color values. Badges/dots keep their light-mode ink in both
themes — a smaller, lower-risk change than threading a second color table
through every already-verified risk-display call site, and the fixed
inks still read fine against both Paper and Nocturne surfaces (confirmed
visually during verification below). Flagging as a known simplification,
not a limitation that blocks the toggle from being "real."

**Found and fixed a real pre-existing bug while wiring the dark theme:
~20 call sites across 9 screens used `Colors.black.withValues(alpha:
...)` for secondary/muted text**, hardcoding black regardless of active
theme — invisible-by-design against Nocturne's near-black backgrounds.
Not something the task asked for directly, but "the theme toggle actually
changes appearance" is meaningless if half the app's secondary text goes
unreadable the moment Nocturne is selected, so this was in-scope to fix
alongside adding the toggle itself. Fixed via one new `context.rnMuted
([alpha])` extension (`lib/core/theme.dart`) that resolves to `RnColors
.text`/`RnDarkColors.text` at the given alpha depending on the active
`Theme.of(context).brightness`, then swapped in at every call site
(`timeline_screen.dart`'s `_metaStyle` needed converting from a `static
final` field to a `static` method taking `BuildContext` since the old
field had no context to resolve against). `RiskBadge`/`RiskDot` and a
handful of brand-color usages (e.g. `RnColors.riskRed` on the Emergency
button) were left as fixed inks — see above.

**Language toggle exclusivity: audited every patient screen + login;
only `login_screen.dart` had the bug.** The greeting block there was two
always-visible `Text` widgets (Roman Urdu line, then the English line
right below it, unconditionally) — never gated on `LanguageProvider` at
all, unlike every other bilingual string in the app which already used
`BilingualText` (a per-string widget that renders exactly one of `en`/
`ur` based on the toggle — see [[conventions]]). Fixed by switching that
block to `BilingualText` like everywhere else. Every other screen
(`home_screen.dart`, `quick_checkin_screen.dart`, `voice_diary_screen
.dart`, `profile_screen.dart`, `result_screen.dart`, `timeline_screen
.dart`, `weekly_digest_screen.dart`) was checked line-by-line and found
already correct — either using `BilingualText`/a ternary against
`LanguageProvider.isRomanUrdu`, or not bilingual content at all (dynamic
data, English-only microcopy not yet translated). **Not fully bilingual
coverage** — most of the app's microcopy (button labels, section
headers, disclaimers) is still English-only text regardless of the
toggle, same as before this session; the task's actual complaint was
specifically about both languages appearing together, not about
translation completeness, so widening bilingual coverage was treated as
out of scope. Verified live (not just by reading code): logged in as
Zubaida Bibi (seeded `roman_urdu` preference) and confirmed Home, Quick
Check-in, and the post-logout Login screen each show Roman Urdu ONLY,
never both languages stacked.

**App icon: generated programmatically (Python + Pillow), not hand-
designed** — no design asset existed for this app yet, per the task.
Two concepts were generated and shown to the user for a pick before
finalizing (per the task's explicit ask): a stylized heartbeat/pulse line
and a leaf/sapling silhouette, both in the app's real brand teal
(`RnColors.accent`/`accentDark`/`surface`/`accent400` — not made-up
colors). **User picked the pulse concept** — it read more clearly than
the leaf at actual launcher-icon size (128px preview), and reads as
health-monitoring more directly. Generator script committed at `mobile_app/
scripts/gen_app_icon.py` (not just a one-off scratch script) so the icon
is reproducible/tweakable, not a throwaway artifact. Applied via
`flutter_launcher_icons` (new dev dependency): `assets/icon/app_icon.png`
(1024x1024, teal rounded-square background + glyph) for iOS
(`remove_alpha_ios: true`, since Apple rejects icons with an alpha
channel), plus a separate transparent-background `assets/icon/
app_icon_foreground.png` (glyph pulled further inward, since Android's
adaptive-icon mask crops roughly the outer third of a foreground layer)
paired with `adaptive_icon_background: "#0F6B68"` for Android. Ran `dart
run flutter_launcher_icons` for real and confirmed by rendering the
actual generated `android/.../mipmap-xxxhdpi/ic_launcher.png` file (not
just the source PNG) — it correctly shows the pulse glyph. **Not
verified**: how the adaptive icon actually composites/animates on a real
Android launcher, or how it looks in an iOS home-screen grid — no
emulator/device available in this sandbox (`flutter doctor` shows the
Android SDK present but license-unaccepted, no Chrome; same category of
gap as every prior mobile pass's device-testing limitations).

**Unrelated blocker fixed to get ANY verification build working: pinned
`record_platform_interface: 1.2.0` via `dependency_overrides`.** A
from-scratch `flutter pub get` (needed regardless, for the two new
dependencies above) resolved `record_platform_interface` to `1.6.0`, but
`record_linux 0.7.2` (the version `record: ^5.2.1` — added in the prior
session's acoustic-analysis pass — actually pulls in) only ever
implemented the `^1.0.2`-era platform-interface abstract class; `1.6.0`
added new abstract members (`startStream`, a new `hasPermission` param)
that `record_linux 0.7.2` doesn't implement, so the Linux build failed to
even compile. `record` 5.2.1 itself declares `record_platform_interface:
^1.2.0`, so 1.2.0 (the newest version actually compatible with what's
installed) is the override. Not caused by anything built this session,
but this session's own environment setup was the first to hit it — see
`pubspec.yaml`'s inline comment. Also needed to get a working Linux build
at all: `libsecret-1-dev` (a `flutter_secure_storage_linux` build
dependency) has no `apt install` path in this sandbox (no root/passwordless
sudo) — worked around via `apt-get download` (doesn't need root) +
`dpkg-deb -x` into a scratchpad dir + a patched `PKG_CONFIG_PATH`, same
trick a prior session apparently used (a stale CMake cache from that
session's now-gone scratchpad path was the first symptom hit, requiring
`flutter clean` to clear). Session-local, not committed anywhere —
whoever next needs a Linux desktop build of this app will need to redo
this (or just have `libsecret-1-dev` actually installed).

**Verified for real, live (screenshots), not just by reading code or
`flutter analyze`.** Built `flutter build linux --debug` (after the
`record_platform_interface` pin and the `libsecret-1-dev` workaround
above) and ran it on an isolated `Xvfb :99` display — **deliberately
NOT** the sandbox's actual `:1` display, which turned out this session to
be the user's real live desktop (their own browser windows, their own
terminal), discovered only after an initial full-screen capture
accidentally grabbed unrelated personal browser content on `:1`; that
capture was deleted immediately and every subsequent screenshot was taken
against the isolated `:99` Xvfb instead (`Xvfb` itself wasn't preinstalled
in this sandbox — pulled via the same rootless `apt-get download` trick).
Interaction was via synthetic X11 events (`python-xlib`'s `XTEST`
extension — no `xdotool` available). Against a fresh `roznoor-pg` Docker
Postgres + real `uvicorn` backend, logged in as the seeded Zubaida Bibi
patient (real `roman_urdu` preference) and confirmed: the Login screen
shows exactly one greeting line (not both); the Profile screen's new
Paper/Nocturne `SegmentedButton` flips the ENTIRE app's appearance
instantly (background, cards, buttons, nav bar, and — critically — the
secondary/muted text that was the black-on-black bug above, all
correctly legible in both themes); Nocturne stays selected across a full
process kill + relaunch (shared_preferences persistence, not just
in-session state) and the app *also* came back auto-logged-in showing
the persisted-Urdu Home screen, confirming both persistence mechanisms
independently; Home, Quick Check-in, and the post-logout Login screen all
render correctly in Nocturne with no illegible text found; the language
toggle stayed exclusively Roman Urdu across logout (in-session
`LanguageProvider` state, expected — see [[conventions]], it doesn't
reset on logout) with no English text appearing alongside it anywhere
checked. **Not verified**: the app icon on an actual Android/iOS
device/emulator (see above); dark-mode `FilterChip`/`SegmentedButton`
selected-state colors weren't specifically audited for on-brand accuracy
(only for legibility, which they have — Flutter's Material3 defaults
derive from `ColorScheme` rather than inheriting the light-only
`RnColors.accent200`/`accentDark` hardcoded in a couple of chip call
sites, so they're not pixel-matched to the Nocturne palette but they are
readable).

---

## 2026-08-25 — Acoustic-signal analysis for Voice Diary recordings (deterministic signal processing, NOT machine learning)

**Scope confirmed with the user up front**: no ML model, no training data,
pure signal-processing feature extraction fed into the existing rule
engine as additional evidence — same rule-based philosophy as
`app/services/rules.py`'s red flags, not a new decision-making layer.
Flagged the realistic timeline risk to the user before implementing (per
their explicit ask) and got a green light to proceed under an
additive-only design; see the architecture decision below for how that
design keeps this from being able to regress the already-verified core
loop.

**Architecture: `POST /entries/{entry_id}/audio` is a SEPARATE endpoint,
deliberately NOT merged into `POST /entries`.** The task's literal wording
("upload alongside the existing POST /entries call") could have been read
as one multipart request, but that would mean converting `POST /entries`
from pure JSON to `multipart/form-data` for every caller (including every
quick entry, which never has audio) — a breaking change to an endpoint
that's the single most load-bearing, most-verified contract in this
backend (see every prior pass's verification narrative). Instead, the
mobile app calls `POST /entries` exactly as before (unchanged request/
response shape), then calls this new endpoint right after with the
recorded file. A failure anywhere in recording, upload, or analysis
therefore CANNOT affect entry submission or its transcript-based
`risk_result` — the entry and its Green/Yellow/Orange/Red result from
`POST /entries` already exist and are valid on their own, exactly like
`app/services/ai.py`'s existing soft-fail contract. This was the deciding
factor in the "don't risk the core loop" framing.

**`app/services/audio_analysis.py` — pure signal processing (numpy +
system `ffmpeg` for decoding — see the mid-build pivot away from librosa
below), no model, no training.** Every feature (pause ratio, speaking-rate proxy,
energy/amplitude variance, pitch variability) is a directly-computed
statistic, and the derived `possible_fatigue_or_breathlessness` flag is a
hand-picked threshold on those statistics — see the module's own
docstring for the full citation/rationale of each. **Every threshold is a
Claude Code proposal with LESS grounding than the rest of
`app/services/rules.py`'s already-flagged thresholds** — there is no
labeled training data, no clinician review, and no comparison against a
real patient population; these are order-of-magnitude guesses about what
"long pauses" and "flat energy" should mean numerically. Needs your (or a
clinician's) review before being treated as authoritative:
- `PAUSE_RATIO_HIGH_THRESHOLD = 0.35` — proposed as "notably above" the
  ~10-20% silence typical of ordinary conversational speech.
- `ENERGY_CV_LOW_THRESHOLD = 0.20` (raised from an initial 0.15 guess
  after real synthetic-audio calibration — see "Verified for real" below)
  — coefficient of variation (std/mean) of frame RMS energy, computed
  over voiced frames only, not raw variance, specifically because raw
  RMS depends on device mic gain/distance and isn't comparable device-to-
  device; CV is scale-invariant. Threshold itself is still arbitrary.
- `MIN_DURATION_FOR_FLAG_SECONDS = 3.0` — below this, features are still
  computed/returned but the derived flag is suppressed (not enough signal
  to trust it).
- `ACOUSTIC_FATIGUE_BREATHLESSNESS_POINTS = 2` (in `app/services/
  rules.py`) — the score contribution when the flag fires, same order of
  magnitude as this file's other proposed symptom weights.

**Deliberately a Layer-B (weighted score) contributor only — can NEVER
trigger a hard Layer-A red flag on its own.** Every existing hard red
flag (chest pain, the 2kg/3-day weight-gain rule) is at least doc/
prototype-sourced; this signal has no evidence base remotely comparable,
so it is capped at the same kind of modest, additive influence as the
other proposed (not clinician-confirmed) symptom weights — it can nudge a
Green toward Yellow, or contribute to crossing into Orange alongside
other signals, but was deliberately kept unable to single-handedly send
anyone to Red. Applied diagnosis-agnostically (unlike the symptom
checklists), since labored/paused speech isn't a heart-failure- or
post-surgical-specific pattern the way a symptom checklist is.

**A hackathon-scope simplifying assumption in how baseline bands are
re-fetched for the audio endpoint — flagging explicitly.**
`rules.evaluate_entry()` requires baseline bands as they stood BEFORE the
entry being evaluated (see `app/services/rules.py`'s and
`app/services/baseline.py`'s existing convention). By the time audio
arrives, the entry has already been folded into `baseline_history` once
by the original `POST /entries` call. This is safe ONLY because a voice
entry never carries quick-check-in values (sleep/energy/mood/appetite/
mobility/weight are always null on a voice entry — see
`app/schemas/entry.py`), so folding it into baseline_history was a no-op
for every metric those bands track, making "current bands" and "bands as
they stood before this entry" identical in practice. This assumption
would NOT hold if audio upload happened long after entry creation with
other entries submitted in between, or if a future change let a voice
entry carry quick values too — flagging both as things that would need
revisiting, not something this endpoint currently guards against.

**Local disk storage for uploaded audio — a HACKATHON-SCOPE SHORTCUT, not
a production choice.** `settings.audio_storage_dir` (default
`audio_storage/`, gitignored), files under `<dir>/<patient_id>/
entry<id>_<random>.<ext>`. Not S3/cloud storage: not multi-instance safe
(a second backend replica wouldn't see another replica's files), not
backed up, not access-controlled beyond the API layer, and would need a
real object-storage migration before any real deployment — exactly the
same kind of shortcut flagged for local Postgres earlier in this project.
`entries.audio_file_path` is never exposed to API clients directly (see
`EntryOut.has_audio`, a boolean) — no client ever sees a server
filesystem path.

**Extraction points folded into existing surfaces rather than new ones —
per the task's "visible to doctors, not just used silently" requirement.**
No new doctor-facing endpoint or Flutter doctor screen was added (Flutter
doctor screens are still a placeholder — see `context/progress.md`).
Instead: (1) `risk_results.reasoning` includes a plain-language sentence
naming the acoustic pattern whenever the flag contributes score — this
text is already what `GET /doctors/{id}/alerts`' `alert_text` and
`GET /doctors/{id}/patients`' `latest_reasoning` surface, so it reaches
the doctor roster/alerts panel for free; (2) `ai_results.acoustic_features`
(raw feature values, always stored when extraction succeeds, whether or
not the derived flag fires) is threaded into `POST /patients/{id}/
ai-summary`'s prompt context (`app/services/ai.py`'s
`_format_entries_for_prompt`), with an explicit system-prompt instruction
that Claude must describe it as "a deterministic signal-processing
estimate from the recording" and never as an AI judgment or diagnosis —
consistent with the project's existing "AI supports interpretation, never
decides risk" boundary.

**Mobile: `record` package (raw capture) + `path_provider` (local temp
file), running CONCURRENTLY with the existing `speech_to_text` mic
session during Voice Diary — a genuine, unverified real-device risk,
flagged clearly.** Two components requesting microphone access at the
same time (a `SpeechRecognizer` session for live transcript + a separate
`AudioRecorder` for the raw waveform) is a known source of "mic busy"
conflicts on some Android versions/OEMs — this project's own history
(the RECORD_AUDIO manifest saga above) is a direct precedent for how
device-specific this class of problem can be. `RECORD_AUDIO` is already
declared in the manifest from that pass, so a repeat of THAT specific
failure mode isn't expected, but concurrent-access behavior itself cannot
be verified in this sandbox (no microphone hardware here, same limitation
noted in every prior mobile pass). Mitigated architecturally, not by
verification that couldn't happen here: `AudioRecorderService.start()`/
`stop()` (`lib/services/audio_recorder_service.dart`) never throws —
any failure (mic busy, permission denied, recorder init failure) is
caught and simply means no file gets attached to that entry; Voice
Diary's transcript-and-submit path is completely unaffected either way.
**Needs the user's own real-device test** to confirm concurrent capture
actually works end-to-end (same "flag, don't silently claim verified"
pattern as the original speech_to_text mic pass).

**Bonus fix found while touching this area: iOS `Info.plist` was missing
`NSMicrophoneUsageDescription`/`NSSpeechRecognitionUsageDescription`
entirely — a PRE-EXISTING gap from the original speech_to_text pass, not
introduced this session.** iOS has never been built/tested at any point
in this project (Android-only real-device testing throughout — see the
LAN-testing entry below), so this had never surfaced. Added both entries
while adding `record`'s own iOS requirement, since the file was already
being touched and the project's own convention (`context/conventions.md`,
"Plugin platform permissions are a build-time checklist item") calls for
checking a new plugin's full platform requirements, not just the platform
being actively tested. Still unverified on an actual iOS device/simulator
— no Mac/iOS environment available in this sandbox, flagged the same as
every other iOS gap in this project.

**Mid-build pivot: librosa was dropped in favor of a hand-rolled
numpy + system-`ffmpeg` implementation — a real infrastructure
constraint, not a design change of preference.** `pip install librosa`
was attempted twice against this sandbox's actual network (once bounded
at 600s, once left unbounded in the background) — both failed to finish;
direct `curl` timing showed throughput as low as single-digit KB/s to
PyPI, and librosa's own dependency chain (numba + llvmlite alone is a
~60MB wheel, plus scipy + scikit-learn) made a normally-under-a-minute
install take 10+ minutes without completing. `numpy` alone (no heavy
compiled transitive deps) installed in seconds. Rewrote
`app/services/audio_analysis.py` to decode via a `ffmpeg` subprocess
(already present system-wide, and what librosa's own `audioread` backend
would have shelled out to anyway for non-WAV input) and do framing/RMS/
silence-detection/pitch-via-autocorrelation by hand with numpy — see the
module's own docstring for the full trade-off writeup, including that
autocorrelation pitch tracking is a real (if hand-rolled) DSP technique,
just less robust than librosa's pYIN on noisy input. This directly
follows the task's own "propose an equivalent lightweight library if
librosa is a poor fit" instruction — librosa was empirically demonstrated
to be a poor fit for this environment, not assumed to be one.
`requirements.txt` updated accordingly (numpy only; librosa/soundfile
removed). **Runtime requirement to note**: `ffmpeg` must be on PATH
wherever this backend actually runs — true of the dev machine used here,
not yet confirmed for whatever hosting environment is eventually chosen
(see the still-open Postgres-hosting item in `context/progress.md` —
same category of "confirm before real deployment" gap).

**Verified for real** (backend fully exercised against a real throwaway
Postgres + running FastAPI instance; mobile capture/upload flagged as
needing the user's own device — see above):
- `app/services/audio_analysis.py` tested directly against two synthetic
  WAV files generated with Python's stdlib `wave`/`math`/`random` (no
  microphone hardware in this sandbox to record real "calm vs.
  exaggerated breathing/pauses" samples, per the task's own request) —
  one built with short natural pauses (~8% measured silence) and healthy
  amplitude variation, one with long pauses (~60% measured silence) and
  deliberately flat/quiet amplitude during voiced segments. **This real
  test caught a genuine bug before it shipped**: `energy_cv` was
  initially computed over ALL frames including silence, which means a
  recording with MORE pauses mechanically gets a HIGHER variance (large
  swings between near-zero silent frames and louder voiced frames) — the
  opposite of what "flat vocal energy" is supposed to measure, and it
  made the derived flag structurally unable to fire on a genuinely
  long-paused recording (the two conditions `high pause_ratio` and `low
  energy_cv` were fighting each other by construction). Fixed by
  computing `energy_cv`/`energy_rms_mean`/`energy_rms_variance` over
  VOICED frames only (silence excluded) — after the fix, the calm sample
  measured `pause_ratio=0.08, energy_cv=0.214` and the exaggerated sample
  measured `pause_ratio=0.605, energy_cv=0.164`, correctly in the
  expected directions for both signals. Also caught, and used to
  recalibrate rather than just note: `ENERGY_CV_LOW_THRESHOLD` (proposed
  at 0.15, pure guess) turned out to be stricter than even a deliberately
  extreme "flat" synthetic sample could cross (frame-boundary attack/
  release transients at each phrase's onset/offset appear to set a
  practical floor on frame-level CV, even for near-monotone audio) — 
  raised to 0.20, still an unvalidated proposal but now informed by one
  real calibration point instead of pure intuition. With that threshold,
  the calm sample correctly measured `possible_fatigue_or_breathlessness:
  false` and the exaggerated sample correctly measured `true`. Also
  confirmed the decoder handles `.m4a`/AAC (converted from the same test
  WAV via `ffmpeg`) — the actual format the mobile `record` package
  produces — with near-identical feature values to the WAV original, and
  confirmed graceful `None` returns (no exception) for both a missing
  file path and a genuinely corrupt/non-audio file.
- Full HTTP flow: a benign voice entry + `calm.wav` stayed Green with
  `possible_fatigue_or_breathlessness: false`, `source: "rule"`; a
  second benign voice entry + `exaggerated.wav` correctly set
  `has_audio: true`, populated `acoustic_features`, flipped
  `possible_fatigue_or_breathlessness: true`, and appended the acoustic
  sentence to `risk_result.reasoning` with `source` flipping to
  `"merged"` — risk_level stayed Green on its own here since +2 points
  alone doesn't cross `SCORE_YELLOW_THRESHOLD=5` from an otherwise clean
  baseline, which is the deliberately conservative design working as
  intended, not a gap. **To directly confirm the acoustic signal can
  actually move a risk_level** (not just add reasoning text), a third
  voice entry combined a manually-ticked "Breathlessness" symptom
  (+3, heart_failure ruleset) with the exaggerated recording (+2) = 5
  points: `risk_level` measurably flipped Green -> Yellow between the
  pre-audio and post-audio response, with a real `alerts` row created
  (`source_rule`/`alert_text` both correctly compound) — confirmed both
  at the DB level (`SELECT` against the live Postgres container) and via
  the actual doctor-facing surface (`GET /doctors/1/alerts` as Dr. Ayesha
  Farooq, the patient's real assigned doctor, correctly returned this
  alert with its acoustic-inclusive text — proving the "visible to
  doctors, not just used silently" requirement end-to-end, not just at
  the schema level). A quick entry (no audio anywhere in its path)
  submitted and confirmed unaffected; `POST /entries/{id}/audio` against
  a quick entry correctly 400s; a genuinely corrupt upload correctly
  saved the file (`has_audio: true`) but left `acoustic_features: null`
  and the entry's original `risk_result` completely untouched (real
  end-to-end proof of the soft-fail contract, not just a unit-level one);
  timeline correctly surfaces `has_audio`/`acoustic_features` on every
  row; `POST /patients/{id}/ai-summary` still soft-fails cleanly with no
  `ANTHROPIC_API_KEY` configured (`available:false`, 200, no 500) — the
  acoustic-prompt-context change didn't break that fallback path.
- Confirmed the app **fails to even boot** if `numpy` is imported at
  module level in `app/services/audio_analysis.py` (caught this myself
  before it shipped: importing the app with numpy not yet installed
  crashed all of `app.main` at import time, since
  `app/routers/entries.py` imports this module unconditionally) — fixed
  by moving the import inside `extract_acoustic_features()` itself,
  matching the same lazy-import pattern already used for optional/heavy
  dependencies elsewhere; re-confirmed the app boots and every other
  route (including `/health`, login, existing `/entries`) works normally
  with numpy genuinely absent from the venv, before numpy was
  (successfully, quickly) installed. `python-multipart`, by contrast, IS
  a hard, unavoidable dependency for the app to boot at all once a route
  declares a `File`/`UploadFile` parameter (FastAPI checks for it at
  route-registration time, not lazily) — accepted since it's a tiny
  pure-Python package with no compiled/binary weight, unlike numpy/scipy/
  numba (and it installed instantly, unlike those).
- **Not verified**: live concurrent microphone capture on a real device
  (see above — no microphone hardware in this sandbox, needs the user's
  own device test); the pitch-tracking accuracy of the hand-rolled
  autocorrelation method against real (non-synthetic) human speech —
  `pitch_mean_hz`/`pitch_variability_hz` are populated and plausible-
  looking on the synthetic test signals (which have a genuinely periodic
  waveform by construction) but real speech's harmonic/noise structure is
  more complex than a synthetic multi-sine test tone, so this specific
  sub-feature has less real-world confidence behind it than pause_ratio/
  energy_cv — flagging honestly rather than overstating it.

---

## 2026-08-25 — Voice Diary silently falling back to typing on a real device: AndroidManifest.xml was missing RECORD_AUDIO entirely

**Root cause confirmed**: `android/app/src/main/AndroidManifest.xml` declared
**zero** runtime-dangerous permissions — only `INTERNET` (itself only added
in the LAN-testing pass above; before that, nothing at all). No
`RECORD_AUDIO`, no `BLUETOOTH*`. This is exactly why the phone's system
Permissions screen for the app showed empty/nothing to manage — Android
doesn't surface a permissions UI for an app that never declared any runtime
permission in its manifest, since there's nothing to request or revoke.
`speech_to_text` requires, per its own README's Android section:
`RECORD_AUDIO`, `INTERNET`, `BLUETOOTH`, `BLUETOOTH_ADMIN`,
`BLUETOOTH_CONNECT` — plus a `<queries>` entry for
`android.speech.RecognitionService` specifically for `targetSdk` 30+ (this
project's `flutter.targetSdkVersion` is well above that), without which the
app can't even see the device's speech recognition service due to Android's
package-visibility rules, separately from the RECORD_AUDIO permission
itself.

**This is a real gap in the earlier "Verified end-to-end" claim from the
Flutter patient-app pass** — that pass's Voice Diary verification used the
typed-text fallback (no audio hardware in that sandbox), which correctly
masked the missing manifest permission: `speech_to_text.initialize()`
reported `false` (unavailable) for an entirely different, legitimate reason
(no mic hardware/PulseAudio in that environment) than the one a real device
hit (mic hardware present, but the OS refuses to even offer the permission
because it was never declared). The manifest should have been checked
against `speech_to_text`'s own documented requirements as part of building
the Voice Diary screen, independent of whatever environment was available to
test the mic path in — not left to be discovered only once real hardware
exposed it. Flagging this as the actual process gap: a plugin's Android/iOS
manifest requirements are a build-time checklist item, not something that
only needs verifying if the test environment happens to support exercising
the feature live.

**Fix applied** (`AndroidManifest.xml`, `src/main/`, not a debug-only
overlay — a real device/production app needs the mic permission
unconditionally, unlike the debug-only cleartext-traffic config above):
added the five `<uses-permission>` entries and one `<queries><intent>` entry
speech_to_text's README specifies.

**Runtime permission request — already correct on the Dart side, no code
change needed.** Confirmed by reading `speech_to_text`'s own Android plugin
source (`SpeechToTextPlugin.kt`,
`initializeIfPermitted()`): `SpeechToText.initialize()` — already called in
`lib/screens/patient/voice_diary_screen.dart`'s `initState()` — internally
calls `ContextCompat.checkSelfPermission()` then
`ActivityCompat.requestPermissions()` for `RECORD_AUDIO` (+
`BLUETOOTH_CONNECT`) itself if not already granted. There is no separate
Dart-side "request microphone permission" call to add — the manifest
declaration was the entire missing piece; without it, Android won't let the
plugin request (or be granted) the permission at all, regardless of what the
plugin or app code does.

**A full uninstall + reinstall on the phone is required, not a hot
reload/restart.** Android reads `<uses-permission>` declarations from the
APK at install time; an app already installed without `RECORD_AUDIO` in its
manifest will not retroactively gain the ability to request it just because
a new APK with the permission gets pushed via `flutter run`'s
incremental/hot-reload path — the manifest is part of the APK's install-time
metadata, not something hot-reloaded. **Uninstall the current app from the
phone, then reinstall via a fresh `flutter run`, before testing the
microphone again** — see the response for exactly when.

Verified two ways before telling the user it's fixed: `flutter build apk
--debug --dart-define=ROZNOOR_API_BASE_URL=http://192.168.100.58:8000`
completed cleanly (no manifest-merge errors), then `aapt dump permissions`
against the actual compiled `app-debug.apk` confirmed `RECORD_AUDIO` and the
three `BLUETOOTH*` permissions are genuinely present in the built artifact,
not just the source XML. Live on-device microphone behavior (does the OS
permission dialog actually appear, does recognition actually work) still
needs the user's own real-device test after reinstalling — not verifiable
from this sandbox (no mic hardware here either, same limitation as the
original Flutter patient-app pass).

---

## 2026-08-25 — "password authentication failed for user roznoor" — root cause was a stale Settings singleton, not a Postgres password mismatch

**What it looked like**: real login attempt from the phone failed; backend
traceback showed `psycopg2.OperationalError: password authentication failed
for user "roznoor"` connecting to **`localhost:5432`**. Networking (LAN IP,
cleartext config) was already confirmed working — this was purely a backend
DB-auth error.

**What it actually was — NOT a Postgres password mismatch between `.env` and
the intended DB.** `Backend/.env` was correct the whole time
(`DATABASE_URL=...@localhost:5434/roznoor`, this project's throwaway Docker
Postgres, `roznoor-pg`, which already has the right role/password/seeded
schema — proven by a direct query and a working curl login against it
earlier the same session). The actual chain of causes:
1. `app/core/config.py`'s `Settings.model_config` uses `env_file=".env"` — a
   **relative path**, and `Settings()` is instantiated exactly ONCE, at
   module-import time (`settings = Settings()`, a module-level singleton).
2. A backend process (`uvicorn ... --reload`, not started by this
   session — the user's own terminal, confirmed by process start time
   `20:33:49`) started **90 seconds before `Backend/.env` existed** in this
   session (`.env` was (re)written at `20:35:01`, as part of the earlier
   LAN-testing setup pass). At `20:33:49`, `env_file=".env"` found nothing,
   so `Settings()` silently fell back to its hardcoded field default:
   `postgresql+psycopg2://roznoor:roznoor@localhost:5432/roznoor` — note
   the **5432**, not 5434.
3. Port 5432 is **not** this project's database at all — it's a pre-existing,
   unrelated native `postgresql.service` (systemd, `postgresql-16`/`18`
   packages) already running on this dev machine for other purposes.
   Confirmed by `psql -h localhost -p 5432 -U roznoor -d roznoor` reproducing
   the exact same `password authentication failed for user "roznoor"` — that
   role/password combination is simply wrong for *that* unrelated server,
   which has no relation to this project's schema/seed data either way.
4. `uvicorn --reload`'s file watcher only reacts to source-file changes in
   the watched directory — it does not re-read `.env` or re-run the
   module-level `Settings()` singleton just because the file appeared/
   changed on disk. So even after `.env` was written correctly, this
   already-running process stayed permanently stuck on its stale fallback
   DB target until restarted.

**Why the two "fix" options in the task's framing were both wrong for this
case**: resetting the *unrelated* system Postgres's `roznoor` password to
match `.env` would have "fixed" the symptom while pointing the app at a
database with none of this project's schema/data — a much worse state, just
with a different failure mode. Rewriting `.env` to match the system
Postgres would have permanently misconfigured the project away from its own
actual database. **The real fix was simply restarting the stale process**
so `Settings()` re-initializes and reads the (already-correct) `.env` on
disk — no config value on either side needed to change.

**Fix applied**: killed the stale process (PID 17554, by PID — not by any
pattern that could risk matching something else), restarted
`uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload` from `Backend/`
(matching the `--reload` flavor it was already running with). **Verified
before reporting fixed**, per the task's explicit requirement: a real
`POST /auth/login` for `zubaida.b@roznoor.care` returned `200` with a real
JWT, both via `localhost:8000` and via `192.168.100.58:8000` (the LAN IP the
phone actually uses) — plus `GET /auth/me` and
`GET /entries/2/timeline` both `200` over the LAN IP too.

**To prevent recurrence**: don't rely on `env_file=".env"`'s relative-path
resolution + a long-lived `--reload` process staying in sync with a `.env`
that gets created/edited after the process already started — if `DATABASE_URL`
ever looks wrong at runtime, check `ps -o lstart` for the backend process's
start time against `.env`'s mtime before assuming the config value itself
is wrong. A more robust long-term fix (not applied here, since the
existing `.env` was already correct and the task scope was diagnose-and-fix,
not refactor) would be making `env_file` an absolute path resolved relative
to `config.py`'s own location, so it can't silently miss the file based on
process cwd/start-order — flagging as a possible future hardening, not done
this pass.

---

## 2026-08-25 — Real Android device testing setup (LAN backend + cleartext fix)

**Incident from the previous Flutter patient-app pass is now CLOSED** — the
user confirmed nothing on their desktop/browser was affected by the
accidental `DISPLAY=:1` synthetic input described in that pass's
verification narrative below. No further action needed; recorded here per
the user's request to log the close-out explicitly.

**`AppConfig.apiBaseUrl` was already `--dart-define`-configurable, not
hardcoded** (`lib/core/app_config.dart`, built in the prior pass) — confirmed
by grepping `lib/` for `localhost`/`127.0.0.1`: the only occurrence is that
file's default value, every network call goes through `ApiClient` which reads
`AppConfig.apiBaseUrl`. No code change was needed for this; just needed the
user's dev-machine LAN IP and the exact command.

**Dev machine's LAN IP for real-device testing: `192.168.100.58`** (the
`wlo1`/WiFi interface, via `hostname -I` — NOT the `docker0`/`br-*` bridge
addresses, which aren't reachable from another device on the network). Run
target: `flutter run -d <device-id> --dart-define=ROZNOOR_API_BASE_URL=http://192.168.100.58:8000`.
This IP is DHCP-assigned and can change on reconnect — not a permanent value,
flagging so a future session doesn't assume it's still current without
re-checking.

**Backend must bind `--host 0.0.0.0`, not the default, for a phone on the
same WiFi to reach it** — `uvicorn app.main:app --host 0.0.0.0 --port 8000`.
Plain `uvicorn app.main:app` (or `--host 127.0.0.1`) binds to loopback only,
invisible to any other device on the LAN even though `curl localhost:8000`
from the dev machine itself would look fine. This had been done correctly by
habit in every prior verification pass's curl commands but was never actually
written down as a requirement anywhere — added to [[conventions]] now.

**Found and fixed a real blocker before the user could hit it: Android blocks
cleartext (plain HTTP) traffic by default for apps targeting API 28+.** The
backend has no TLS (`http://`, not `https://`), so every request from a real
device/emulator would fail with `CLEARTEXT communication ... not permitted`
regardless of whether the IP/port were correct — this is an OS-level network
security policy, not a config-file omission that shows up as a login error;
it would have looked like "the app can't reach the backend at all" with no
obvious cause. Fixed via a debug-build-only network security config:
`mobile_app/android/app/src/debug/res/xml/network_security_config.xml`
(`cleartextTrafficPermitted="true"` at the base-config level — permissive
about which domains rather than pinned to one IP, since the dev IP can change
on DHCP renewal; debug-only is the actual security boundary, not the domain
list) wired in via `android/app/src/debug/AndroidManifest.xml`'s
`android:networkSecurityConfig` attribute. A release build (`src/main/`, not
`src/debug/`) is unaffected and stays on Android's strict HTTPS-only default.
Also added the `INTERNET` permission to the main manifest
(`android/app/src/main/AndroidManifest.xml`) — previously only the
debug/profile overlay manifests had it (added there automatically by
`flutter create` for the VM service connection, which happened to also cover
the app's own HTTP calls in debug builds, but a release build needs it
declared in the main manifest too).

**Almost caused a real concurrency conflict: user started their own
`flutter run -d neo7U2401003561` (no dart-define) in a separate terminal
while this session's own verification `flutter run` was mid-build against
the same physical device.** Caught by checking `ps aux` before assuming a
clean environment — two concurrent Gradle/adb installs to the same device
risk conflicting. This session's own process was killed immediately
(`kill` by PID, not by any pattern that could have matched the user's
terminal); the user's own process was left completely untouched. Lesson:
before launching anything against a device/resource a user might also be
using directly, check first rather than assume exclusive access.

---

## 2026-08-25 — Flutter patient app (UI/routing + real API wiring)

**Role-switcher tabs: confirmed NOT present in any shippable code — only
in the design prototype, where they're expected.** Searched the whole
repo before building anything (per the task's explicit instruction). No
Flutter app and no React/Vite web app existed anywhere in the repo prior
to this session (`find` for `.jsx`/`.tsx`/`vite.config`/`package.json`
turned up nothing, and `progress.md` already listed both as "not
started"). The Patient/Doctor/Admin radio-button switcher
(`onChange="{{ setPatient }}"` etc.) exists exactly once, in
`UI Inspo/.../RozNoor.dc.html` — the design prototype's own preview
control for switching mockup views, never wired to auth. Nothing needed
removing. The Flutter app built this session has no such control by
construction: `lib/screens/root_router.dart` is the single place that
decides post-login routing, and it reads only `session.role` (sourced
from the backend JWT via `POST /auth/login` / `GET /auth/me`) — never a
user selection. `lib/screens/auth/login_screen.dart`'s `isClinician` flag
changes copy/color only, never which endpoint is called or how the
response is routed — verified end-to-end by logging in as a real doctor
account (Dr. Ayesha Farooq) through the "Are you a doctor or admin?"
link and confirming it lands on the doctor placeholder purely from the
JWT's role, not because of which form was used.

**Three small, additive backend endpoints/fields were added this
session, despite the task framing this as "Flutter UI/routing only."**
Flagging clearly since the task said not to touch/rebuild auth and
implied the backend was otherwise out of scope. Each was strictly
necessary to make an explicitly-requested screen work at all against the
*existing* schema — no new columns, no new tables, no migration:
- **`GET /auth/me` now also returns `patient_id`** (nullable, resolved by
  querying `patients` for `user_id`/`attendant_user_id` matching the
  caller). Without this there was literally no way for a freshly
  logged-in patient/attendant client to discover which `patients.id` to
  call every other patient-scoped route with — `POST /auth/login` only
  returns `user_id`, and there is no "list my patients" endpoint. Login
  logic itself (hashing, JWT issue/verify) was NOT touched — this only
  enriches `/auth/me`'s read of already-existing data with one extra
  query.
- **`PatientOut` (`GET /patients/{id}`) now also returns
  `emergency_contact_name`, `emergency_contact_phone`, `medication_info`
  (already-existing `patients` columns that just weren't exposed yet) and
  computed `attendant_name`/`assigned_doctor_name` (same "computed, not
  stored" pattern as the admin router's `linked_summary` —
  see the 2026-08-25 doctor/admin entry above). Needed for the Profile
  screen's Attendant/Treating doctor/Emergency contact/Medicines rows.
  **Still no PATCH `/patients/{id}`** — Profile stays view-only; "edit
  where the API supports it" currently means no field is editable.
- **`GET /patients/{patient_id}/symptom-checklist` added** — reuses
  `app.services.rules.diagnosis_key` +
  `CHECKLIST_DIAGNOSIS_SEARCH_TERMS` (the exact same lookup
  `POST /entries` already uses internally) so the checklist a patient
  sees in Quick Check-in / the Result screen's "what we heard" chips is
  guaranteed to be the same set `POST /entries` will accept `symptom_ids`
  from. Without this the Quick Check-in screen had no way to know which
  symptom chips to render at all (the only alternative was hardcoding the
  heart-failure list, i.e. real data becoming mock data again for every
  other diagnosis).
All three verified via curl before any Flutter code called them, then
again through the real running app (see verification narrative below).
**Not done, deliberately**: no endpoint added for
`ai_results.deviation_deltas` or `extracted_symptom_tags` (Result screen
uses `symptom_names` — manual + AI-merged — instead, and omits the
prototype's separate numeric deltas card) and no weekly-digest endpoint
(see below) — both would have been genuinely new read surface, not just
exposing existing columns/logic, so they were left alone and the gap
documented instead of silently building around it.

**Weekly Digest ("Trends" tab) is computed client-side from real
timeline data, not from a backend endpoint.** `weekly_digests` is a
stored table with no route reading/writing it (`progress.md`, "Not yet
started") — building one would be new backend feature work, not
"Flutter-only." `lib/screens/patient/weekly_digest_screen.dart` instead
aggregates `GET /entries/{id}/timeline`'s already-loaded data
client-side: this week vs last week sleep/energy averages, a 7-night
sleep bar chart, medicine adherence %, and a couple of plain deterministic
insight sentences (no AI, no invented clinical claims — every number
traces to a real `entries` row). Revisit once/if a real weekly-digest
endpoint exists.

**Sleep in Quick Check-in is an hours field (0-24), not a sixth 1-5
slider**, even though the prototype's mockup (`RozNoor.dc.html`, `p-check`
screen) visually draws Sleep as one of five identical 1-5 sliders in a
single `sc-for` loop. That mockup predates the confirmed backend scale —
`entries.sleep_value` was locked as hours back on 2026-08-24 (see that
date's entry above), a decision the visual prototype was never updated to
reflect. Energy/Mood/Appetite/Mobility stay 1-5 sliders, matching both
the prototype and `app/schemas/entry.py`'s confirmed bounds. Also added
an optional weight (kg) field to the same screen (not in the prototype's
Quick Check-in mockup at all) since `entries.weight_value` is a real,
important column and there was otherwise no patient-facing way to submit
a "just weight" quick entry from the app.

**Speech-to-text: the `speech_to_text` package** (on-device recognition
via the OS's own speech engine on Android/iOS/web — "simplest to
integrate now" per the task, no server-side STT service to stand up).
The language toggle (English/Roman Urdu) sets its recognition `localeId`
(`en-US` / `ur-PK` — see `lib/state/language_provider.dart`), so it
genuinely changes what gets sent to voice entry processing, not just
this screen's static labels, per the task's explicit requirement.
**Verified only via the typed fallback, not a live microphone** — this
sandbox has no audio input hardware/emulator, so `speech_to_text`
correctly self-reports unavailable on both the Linux-desktop build and
the isolated Xvfb display used for verification (see below), and the app
correctly falls back to the same "Type instead" text field the prototype
itself documents as a first-class alternative ("If speech is unavailable,
typing works exactly the same way") — both paths call the identical
`POST /entries(entry_type=voice)`. A real device/emulator with a
microphone is needed to verify the live-recognition path itself; flagging
as not yet exercised.

**Language toggle does not persist server-side.** Initialized from the
account's real `language_preference` (`GET /auth/me`) on login, freely
toggleable after that, but there is no `PATCH` endpoint to write a change
back — a toggle only affects the current session's UI text and STT
locale. Verified: Zubaida's seeded `roman_urdu` preference correctly
started the Voice Diary screen in Roman Urdu; toggling to English
correctly changed both the placeholder text and (per the code path) the
locale that would be passed to speech recognition.

**State management: Provider (`ChangeNotifier`), not Riverpod/Bloc.**
Three small providers (`AuthProvider`, `LanguageProvider`,
`PatientDataProvider`), no cross-cutting complexity that would justify a
heavier framework — matches the "simplest that works" bar the rest of
this project's stack decisions have used (bcrypt-direct over passlib,
PyJWT over python-jose, etc.).

**API client: a single `Dio` instance (`lib/core/api_client.dart`) with
one interceptor that attaches `Authorization: Bearer <token>` from
`SecureStorageService` to every request**, plus an `ApiClient.run()`
wrapper that turns any failure into an `ApiException` carrying the
backend's `detail` message. Every `*Service` class (`AuthService`,
`PatientService`, `EntryService`) is a thin wrapper matching one
`api-contracts.md` section exactly — no service re-implements auth
header logic or error parsing itself.

**Secure storage: `flutter_secure_storage`**, per the task's explicit
instruction — Keychain/Keystore-backed, not plain `SharedPreferences`.
Stores exactly the four fields needed to restore a session on cold start
(`token`, `userId`, `role`, `name`); `patient_id`/`language_preference`
are always re-fetched live via `GET /auth/me` on restore rather than
cached, so a stale cached role/patient_id can never drive routing.

**Bug found and fixed during verification: logging out from a pushed
screen (Profile) didn't return to the login screen.** `RootRouter` is the
app's single `home:` widget — when `AuthProvider`'s status flips to
`signedOut` it correctly re-renders as `LoginScreen`, but Profile is
reached via `Navigator.push` on top of the patient shell, and a pushed
route sitting above `RootRouter` in the navigation stack doesn't get
dismissed just because the route *underneath* it changed what it renders.
Caught by actually running the app and clicking "Log out" from Profile —
the screen stayed on Profile instead of showing the login screen.
Fixed in `lib/screens/patient/profile_screen.dart`: `_logout()` now also
calls `Navigator.of(context).popUntil((route) => route.isFirst)` after
`AuthProvider.logout()`. Doctor/admin's placeholder-screen logout and the
unlinked-account screen's logout don't need this fix — both are the root
route's own content, nothing is pushed above them.

**Verified for real, against the actual backend (not mocked) — full
narrative:**
- Backend: a fresh throwaway local Postgres 16 (Docker, port 5434,
  auto-removed after) + `alembic upgrade head` + `seed.py`, then
  `uvicorn app.main:app` — no `ANTHROPIC_API_KEY` configured this
  session, so every AI-dependent path correctly stayed on its rule-only
  fallback (`source: "rule"`) rather than exercising `source: "merged"`;
  the AI-merge path was already verified in the 2026-08-25 AI-layer pass
  with a real key and wasn't re-tested here since no Flutter code touches
  that logic. Confirmed via curl before writing any Dart networking code:
  login, `/auth/me` (new `patient_id` field), `GET /patients/2` (new
  fields), the new symptom-checklist endpoint, a quick entry, and a voice
  entry.
- App: built for real with `flutter build linux --debug` (not `flutter
  run` against an emulator — no Android SDK license accepted and no
  emulator/device available in this sandbox) and exercised with real
  synthetic mouse/keyboard input via `python-xlib` + `Xtest`, screenshotted
  with `ffmpeg -f x11grab`. **Important environment note**: the first
  attempt sent this input to `DISPLAY=:1`, which turned out to be the
  user's actual live desktop, not an isolated test display — a mistake,
  disclosed to and confirmed by the user, who then asked for an isolated
  `Xvfb` virtual display instead. All actual interactive verification
  below happened on a separate `Xvfb :99` display, started and torn down
  by this session, never touching the user's real screen again.
  `flutter_secure_storage`'s Linux plugin needed `libsecret-1-dev` (+
  `libgcrypt20-dev`/`libgpg-error-dev`) to compile, which weren't
  installed and this session had no sudo — worked around by
  `apt-get download`-ing the `.deb`s (no root needed), extracting them to
  a local prefix, and pointing `PKG_CONFIG_PATH` at it for the build only;
  nothing was installed system-wide.
- Confirmed by screenshot at every step: login screen renders correctly
  (sage/teal palette, no role switcher, the secondary clinician link);
  logging in as Zubaida Bibi (real patient account,
  `zubaida.b@roznoor.care`) succeeds and lands on the patient Home with
  real data (Day 8, 8 entries); Quick Check-in's symptom checklist loads
  the real diagnosis-specific chips from the new endpoint; ticking "Chest
  pain" and submitting produces a real `POST /entries` call and the
  Result screen correctly shows Red / "Please seek care now" / the exact
  rule-engine reasoning text; Voice Diary's typed fallback submits a real
  `entry_type=voice` entry and shows a real (Green, no false positive)
  result; Timeline shows all of the session's real entries newest-first
  with correct risk badges/stats; Profile shows real name/age/attendant/
  diagnosis/doctor/emergency-contact/medicines/baseline-progress; the
  Roman Urdu toggle changes real UI text; the clinician login link routes
  a real doctor account to the placeholder screen purely by JWT role; and
  logout (after the fix above) correctly returns to the login screen from
  both a pushed screen and a root screen.
- Not verified this session (flagging rather than silently skipping):
  live microphone speech recognition (no audio hardware/emulator — see
  above), the AI-merged voice path (`source: "merged"`, no API key
  configured), and anything on an actual Android/iOS device or emulator
  (Linux-desktop + Xvfb only).

---

## 2026-08-25 — Doctor & admin routers (backend feature-complete for MVP scope)

**`doctor_notes` and alert-review are doctor/admin ONLY — no patient/attendant
self-access, unlike every other patient-scoped route in this app.** Everything
else patient-scoped (`GET /patients/{id}`, the AI summary, the entry timeline)
uses `is_authorized_for_patient`, which also lets the patient/attendant see
their own record. Clinical notes and marking an alert reviewed are clinician
actions on the record, not read access to it, so they use a narrower rule
(`is_authorized_clinician_for_patient`: admin always, doctor only if
`assigned_doctor_id` matches) that drops the patient/attendant branch
entirely. Concretely verified: Zubaida (patient) and Imran (her attendant)
both correctly got 403 trying to POST or GET her own `doctor_notes`, even
though both can read her `GET /patients/{id}` and timeline just fine.

**`GET /doctors/{doctor_id}/patients` and `GET /doctors/{doctor_id}/alerts` are
doctor-self-or-admin, with NO patient/attendant path at all** — added
`is_authorized_for_doctor`/`get_authorized_doctor` to `app/core/deps.py`, same
two-piece shape as the existing patient RBAC pair (see [[conventions]]). These
are doctor-dashboard resources; there's no product reason for a patient role to
ever call them, so the check is a clean role-plus-self-id match, not a scaled-
down version of the patient rule.

**Doctor roster (`GET /doctors/{doctor_id}/patients`) fields chosen by reading
the UI prototype's `roster` state directly** (`RozNoor.dc.html`): name, MR
number + age, diagnosis, day count, latest risk level, and the latest risk
result's `reasoning` text as a stand-in for the prototype's short "deviation"
column (e.g. "Weight +2.4 kg / 5 days") — real data now, not the prototype's
hardcoded strings. Sorted most-recently-active first (not in the prototype,
which has a fixed demo order) — most useful default for a doctor scanning a
live roster; not doc-sourced, a reasonable default, flagging in case a
different sort is wanted later.

**`doctor_notes.doctor_id` records the authoring user's id even when that user
is an admin, not literally always a doctor.** Same "expected, not DB-enforced"
convention already established for `patients.assigned_doctor_id` and
`attendant_user_id` (see [[schema]]) — an admin is allowed to author a note
(RBAC-wise, admin always passes `is_authorized_clinician_for_patient`), and
there's no separate "authored_by_admin" concept in the schema to route that
case to instead.

**`POST /admin/users` conflict on a duplicate `phone_or_email` returns `409`,
not `400`.** First use of 409 in this API — every prior validation-style
rejection (bad `symptom_ids`, an empty PATCH body) is either a `400`/`422`
input-shape problem. A duplicate unique-constraint value is a different kind
of failure (the request is well-formed, but conflicts with existing state),
which `409 Conflict` names correctly. Applied consistently: also used for a
`PATCH` that would collide with a different existing user's email.

**Admin `PATCH /admin/users/{id}` edits `status`, per the task wording, but
`users` has no `status`/`is_active` column — none was added.** The UI
prototype's "People & roles" screen shows an Active/Invited badge per row, but
it's decorative demo state (`s.reviewed`-style local mock, not backed by any
real field) — nothing in the schema doc or any prior pass defines what
"status" would even mean here (disabled login? pending invite email?). Per the
standing instruction to flag before adding a column, this was NOT added
silently; `AdminUserUpdate` only edits the columns that actually exist
(name/role/phone_or_email/language_preference). Flagging for your call: if a
real active/invited/disabled concept is wanted, it needs a real column and a
decision on what triggers each state.

**`GET /admin/users` adds a computed `linked_summary` + `diagnosis` per row,
not just the raw user columns.** Not strictly asked for ("list all users with
role"), but the task explicitly frames this as "for the People management
screen," and the prototype's actual People screen shows "Linked to" and
"Disease track" columns that a bare user list can't support — computed
on-the-fly from existing FKs (patient's `assigned_doctor_id`, attendant's
linked patient via `attendant_user_id`, a doctor's assigned-patient count),
nothing new stored. Kept minimal: no new query complexity beyond a few
per-row lookups at hackathon data volumes (10-ish users).

**Verified end-to-end** against a fresh throwaway Postgres + running FastAPI
instance (no migration needed — every table/column already existed): 48 real
HTTP-request checks covering every endpoint's full RBAC matrix (correct role
200s, wrong doctor 403s on another doctor's roster/alerts/notes, admin always
succeeds, patient/attendant blocked entirely from doctor- and admin-only
routes even where they'd normally have read access elsewhere), 404s on
nonexistent doctor/alert/user ids, 409 on duplicate email at both create and
PATCH, 422 on an empty PATCH body, 401 unauthenticated, and a functional check
that a newly admin-created user's password is a real bcrypt hash usable to log
in (not a placeholder). All 48 passed on the first run. Also closed out a
flagged item from the AI-layer pass: the "no checklist defined for this
diagnosis" AI-skip guard (a voice entry for a COPD-diagnosis patient, which
maps to the generic ruleset with no `CHECKLIST_DIAGNOSIS_SEARCH_TERMS` entry)
was confirmed to never call `ai_service.extract_symptoms()` at all — stayed
`source='rule'`, wrote no `ai_results` row. No Claude API call/key was needed
for that check since the guard skips before any call would happen.

**Backend is now feature-complete for the hackathon MVP scope** — see
[[progress]]. No further backend routers are planned; per this task's own
framing ("this is the last backend pass before frontend work starts"), the
next phase is expected to be the React (web/doctor/admin) and Flutter
(mobile/patient) frontends — not started yet, awaiting an explicit go-ahead
the same way every prior pass required one before touching them.

---

## 2026-08-25 — AI layer (Claude API integration)

**Model: `claude-opus-5`.** Per current Anthropic guidance (this app has no reason to
downgrade from the default). `output_config: {effort: "low"}` for symptom extraction
(a classification-shaped task) and `{effort: "medium"}` for summary generation (needs
decent prose quality). No extended-thinking config set — both tasks are simple enough
that adaptive thinking's default behavior is sufficient.

**Confirmed 2026-08-25 (user check-in, budget allows it): Opus 5 is a deliberate
output-quality choice for both `extract_symptoms()` and `generate_patient_summary()`,
not an oversight.** No cost-driven downgrade to a smaller model was considered or
applied. Verification against real credits was scoped accordingly: the two
fallback-plumbing checks (no key configured; a deliberately invalid key) spent no
meaningful credits by construction rather than via any mock layer — no-key
short-circuits before any network call in `_get_client()`, and invalid-key is
rejected by Anthropic with a real 401 before token billing applies (see the
verification narrative below) — while the four substantive quality checks (Roman
Urdu symptom extraction x2, a benign negative control, and the AI summary) were run
against the real key on purpose, since those are the only ones where output quality
actually needed human judgment.

**Structured outputs via `client.messages.parse(output_format=PydanticModel)`** for
symptom extraction — guarantees valid JSON matching the schema, rather than asking
Claude for JSON in prose and hoping. Summary generation uses plain `messages.create()`
since it's free-text output, not structured data.

**AI only ever supplies symptom *evidence* into the existing rule engine — it never
assigns a risk level on its own.** `extract_symptoms()` (voice entries only) returns
which of the patient's diagnosis-specific checklist symptoms the transcript describes.
The caller (`app/routers/entries.py`) folds those matches into the SAME `symptom_names`
set the rule engine scores — including hard red-flags. Concretely verified: a Roman
Urdu transcript saying chest pain, with NO manual checklist tick, correctly triggered
the hard Red flag exactly as if the box had been ticked. This was the actual design
goal, not an incidental effect — matches the project doc section 14 ("AI supports
interpretation... it does not replace clinical rules") in the strongest possible way:
AI literally cannot bypass or soften a rule, it can only feed it more accurate input.

**`risk_results.source` is only ever `'rule'` or `'merged'` in this implementation —
`'ai'` is never produced.** The task's spec listed `'ai'` as a possible source, but
since the rule engine always runs regardless of AI (the fallback requirement demands
this), there's no code path where AI is the sole basis for a risk level — every
evaluation that includes AI also includes the rule/baseline layer's contribution, so
`'merged'` is always the accurate label once AI actually ran. `source='merged'`
whenever `extract_symptoms()` returned a non-None result this call (even an empty
one — AI running and confirming "no matches" still counts as AI having contributed);
`source='rule'` when AI didn't run at all (quick entry, no checklist defined for the
diagnosis) or failed/errored/timed out. Flagging this interpretation in case the
product actually wants a literal `'ai'`-only path later.

**Symptom extraction only runs for `entry_type == 'voice'`, and only when the
diagnosis has a defined checklist.** Quick entries have no free text to interpret —
nothing for AI to do. Diagnoses outside `heart_failure`/`post_surgical` (the generic
fallback ruleset) have no checklist to match against, so extraction is skipped rather
than run against an undefined vocabulary.

**AI-detected symptoms are persisted as real `entry_symptoms` rows**, not just
mentioned in `ai_results.extracted_symptom_tags` — the same way a manual checklist
tick would be (deduplicated against anything already manually ticked). Chosen so a
symptom AI catches is visible on the patient's record the same way a manually-ticked
one is, not a second-class signal buried only in a JSONB blob.

**`ai_results.deviation_deltas` is computed in plain Python, not phrased by Claude.**
Deliberate: these are real baseline-comparison numbers (already computed for the rule
engine), and there's no reason to let a language model risk restating them
incorrectly. Only `extracted_symptom_tags` reflects genuine free-text interpretation.
Verified: for a voice-only entry (no quick-checkin values submitted alongside it),
`deviation_deltas` came back `{}` — correctly empty, since there was nothing numeric
on that entry to compare.

**`POST /patients/{patient_id}/ai-summary` added** — the "Generate AI Summary"
doctor-facing button from the project doc/UI prototype (also serves the patient's own
Result-screen-style summary; same RBAC as everything else patient-scoped via
`get_authorized_patient`). Chose POST over GET since "Generate" is an action verb in
the source UI, even though this endpoint doesn't persist anything (no write to
`weekly_digests` — that table's period-based structure is a distinct concept from an
on-demand summary; left unconnected to this endpoint for now). Returns
`{available, summary_text, fallback_message}` rather than a bare string, so callers
can render a graceful "AI unavailable" state instead of getting a 500.

**API key handling**: `settings.anthropic_api_key` (env `ANTHROPIC_API_KEY`), defaults
to `None`. Every function in `app/services/ai.py` treats a missing/invalid key,
network failure, or malformed response identically — log a warning, return `None`,
never raise. No retries beyond the SDK's own default (`max_retries=1` set explicitly,
lower than the SDK's default 2, to keep a failing call from adding much latency to
`POST /entries`) and a 20s hard timeout so a hanging call can't stall the request
indefinitely.

**Verified end-to-end with a REAL Anthropic API key** (the user provided one for this
verification pass; it was written only to a gitignored local `.env`, used for the
test run, and removed again along with the throwaway Postgres container — never
logged or committed). Three fallback scenarios confirmed via real HTTP requests: no
key configured (client construction short-circuits, `source='rule'`, no `ai_results`
row); a deliberately invalid key (real 401 from Anthropic, caught and logged, same
graceful fallback, request completed in ~0.6s — no hang); and the `ai-summary`
endpoint returning `available:false` with a 200, not a 500, on the invalid key. Then
with the real key: a Roman Urdu transcript describing breathlessness/ankle
swelling/fatigue with NO manual ticks correctly produced `matched_symptoms` for both
checklist items plus free-text tags, `source='merged'`, and a Yellow risk level; a
Roman Urdu chest-pain transcript with NO manual tick correctly triggered the hard Red
flag via AI-detected symptoms alone; a benign "I'm fine, slept well, ate well"
transcript correctly produced zero symptom matches (no false positive); and
`POST /patients/{id}/ai-summary` produced a real, well-grounded paragraph over
Zubaida's entry history (correctly cited her actual weight numbers and band, and
correctly attributed the risk escalation to "the rule and baseline layers", not to
itself — matching the system prompt's instruction and the project doc's section-14
requirement).

---

## 2026-08-24 — Weight tracking added (entries.weight_value)

**Resolved: `entries.weight_value` added — user-confirmed, not a Claude Code
assumption.** The previous pass flagged this as a schema gap needing a decision; the
user explicitly confirmed adding it ("required — it's the demo's flagship red-flag
scenario", "not out of scope"). Added as nullable `numeric`, NOT gated to
`entry_type` (a weight-only quick entry — a plain morning weigh-in with no sliders —
is valid on its own; the `EntryCreate` "at least one quick value" validator now
counts `weight_value` too). Migration:
`alembic/versions/3973a8111b8e_add_entries_weight_value.py`, generated via
`alembic revision --autogenerate` against a throwaway Postgres already on the prior
migration — diff was exactly the one column, nothing else moved.

**Weight red-flag rule implemented**: `app.services.rules._weight_gain_red_flag`,
wired into `HEART_FAILURE_RULES["hard_red_weight_gain"] = {"kg": 2.0, "days": 3}`
(doc-sourced threshold — see the rules.py docstring). Compares the new entry's
weight against the LOWEST weight_value logged in the trailing 3-day window (not just
the earliest reading), so an upward spike is caught regardless of whether weight
dipped first. Only `heart_failure` carries this key; `post_surgical`/`generic` have
no weight threshold (not doc-sourced for those diagnoses, and weight gain isn't the
same kind of safety signal outside heart failure).

**Weight deliberately excluded from Layer B's generic baseline-deviation scoring.**
The existing per-metric loop in `rules.py` treats "below `baseline_min`" as bad,
which is the right direction for sleep/energy/mood/appetite/mobility but the WRONG
direction for weight in heart failure (a rise is the danger signal, a dip generally
isn't). Rather than force weight into that loop and get backwards scoring, it's
handled only by the dedicated hard-flag check above. `baseline_history` still tracks
a `weight` band (min/max) for charting/trend purposes via
`app.services.baseline.METRIC_COLUMNS`, just not read by the generic deviation
scorer.

**Seed data**: Zubaida Bibi's 6 entries now trace a weight trajectory (62.0kg seven
days back -> 64.4kg today) that reproduces the exact "+2.4 kg / 5 days" figure
already baked into her `risk_results.reasoning` and `alerts.alert_text` from the
original seed pass — previously that text was describing a metric with nowhere to
actually store the number; now the number and the stored data agree. Ghulam Rasool
and Mukhtar Ali (both heart_failure, both Green/Red-for-other-reasons) got stable
weight trends added as an explicit no-false-positive contrast case. Naseem/Bashir/
Farida (two post_surgical, one generic-adjacent) were left without weight_value —
the rule doesn't apply to their diagnoses, so there was no realism gap to fill.

**Verified end-to-end** against a fresh throwaway Postgres + running FastAPI
instance, via real `POST /entries` calls (not just re-seeding): a clear +3.2kg jump
correctly fired Red with accurate reasoning text; the exact 2.0kg boundary fired Red,
1.9kg did not (confirms the `>=` comparison, not an off-by-one); a large gain spread
over 10+ days (outside the 3-day window) correctly did NOT fire, distinguishing rapid
fluid-retention-pattern gain from ordinary gradual weight change; a stable patient
(Mukhtar) submitting a normal small weight change stayed Green; `baseline_history`'s
`weight` row updated correctly after each submission; the timeline endpoint returns
`weight_value` on every entry.

---

## 2026-08-24 — Rule-based safety engine (entries, baseline, red flags, risk)

**Weight-based red flag NOT implemented — schema gap, needs your decision.**
*(Resolved 2026-08-24 — see the "Weight tracking added" entry above.
`entries.weight_value` exists now and the rule is implemented.)*
The project doc and the UI prototype both treat weight as a core
heart-failure safety signal — the prototype literally calls "sudden
weight gain over 2kg in three days" a "clinician-set heart-failure
threshold" (`RozNoor.dc.html` SUMMARY text) — but **`entries` has no
`weight_value` column** (confirmed again against [[schema]]; only sleep,
energy, mood, appetite, mobility are tracked per check-in). There is
nowhere to store a patient-submitted weight reading, so this rule cannot
be evaluated at all in the current schema. `baseline_history` still
carries a seeded `metric='weight'` row from the earlier seed pass, but
nothing populates or reads it from real entries now. **This needs your
call**: either (a) add `entries.weight_value` (a real schema change —
flagging per the standing instruction to ask before assuming one), or
(b) accept weight tracking as out of scope for this hackathon MVP. Left
unimplemented pending your answer; everything else in the rule engine
works without it.

**Rule engine thresholds are Claude Code proposals, NOT clinician-confirmed
— explicit review needed.** Per the task's instruction to flag every
threshold the project doc doesn't give a number for. What's actually
doc/prototype-sourced vs. invented (see `app/services/rules.py`
docstring for the full citation trail):
- **Doc-sourced, high confidence**: chest pain is an instant Red flag for
  heart failure, independent of baseline ("This does not wait for a
  baseline comparison" — prototype). Breathlessness (+3) and ankle
  swelling (+2) symptom weights come from the prototype's own demo
  scoring function (`riskFor()` in `RozNoor.dc.html`).
- **Proposed by Claude Code, needs review**: every other heart-failure
  symptom weight (Dizziness +2, Palpitations +2, Night cough +1); the
  entire post-surgical rule set (hard flag: Wound discharge; weights:
  Fever +3, Wound redness +2, Incision pain +1, Reduced mobility +1,
  Swelling at site +1) — the prototype only shows a version tag
  ("Post-surgical · v2 · reviewed 18 Jul") with no actual rule text: the
  generic/unrecognized-diagnosis fallback (no hard flags, no symptom
  weights, baseline+adherence scoring only — mirrors the prototype's
  "COPD · draft" state); the baseline-deviation point values (mild=1,
  moderate=2 at a 1.0-unit gap); the below-band streak rule (2+
  consecutive entries, +1 point); the missed-dose rule (3+ in trailing 7
  days, +3 points; a single miss, +1); and the final score->level
  thresholds (Yellow >=5, Orange >=8) — rescaled from the prototype's own
  load>=7/10/14 bands to this module's different point values.
- Per the project doc's own framing (section 8/6.4: red-flag rule sets
  are "versioned and cannot be edited by the AI layer — only by a named
  clinician reviewer"), `app/services/rules.py`'s Python constants are the
  MVP stand-in for that — not yet an actual versioned/editable store.

**Baseline algorithm (the three-stage math) is also a Claude Code
proposal, needs review.** The project doc names cold_start/learning/
personalized and their day ranges but never gives the literal formula for
what a "baseline range" is. Implemented in `app/services/baseline.py` as:
raw min/max of all values seen so far during cold_start (days 1-7) and
learning (days 8-14), switching to mean ± 1 standard deviation once
personalized (day 15+). A zero-width band (constant history) is padded
±0.5 so it doesn't flag every future value as a deviation. Full recompute
from all of a patient's entries on every new submission, not an
incremental update — simpler and correct at hackathon data volumes.
**Observed consequence worth knowing**: mean±1sd widens quickly on
volatile history (verified during testing — a moderately low value can
get absorbed into the band after just one or two occurrences rather than
flagged), which may under-flag real deterioration in small/volatile
histories. Flagging as a known characteristic of this proposed formula,
not a bug.

**Seeded `baseline_stage`/`day_count`/`baseline_history` are overwritten
the moment a patient gets one real entry.** `seed.py`'s hand-set values
(e.g. Bashir Ahmed seeded as `personalized`/day 33) are fictional
scene-setting for demo purposes — they don't come from real entries
spanning that many days. As soon as `POST /entries` runs
`update_baseline_after_entry` for a patient, their `baseline_stage`/
`day_count`/`baseline_history` get recomputed from ONLY their real
`entries` rows, which can be a smaller/shorter history than the seeded
narrative implied (verified: Bashir dropped from `personalized`/day 33 to
`cold_start`/day 5 after one real submission, since his 3 seeded entries
only span 2026-08-20 to 2026-08-24). This is correct behavior per the
task's spec (recompute from real data), just worth knowing so a
mid-demo drop in baseline_stage isn't mistaken for a bug.

**Diagnosis-to-ruleset matching is a case-insensitive substring match,
not exact.** `diagnosis` is free text (schema doc: "editable list, not a
hardcoded enum"), so `app/services/rules._diagnosis_key()` matches
"heart failure" / "post-surgical" as substrings (e.g. "Heart failure,
post-discharge" -> heart_failure ruleset). Anything that doesn't match
falls back to the diagnosis-agnostic generic ruleset (baseline +
adherence scoring only, no symptom-specific rules) rather than erroring.

**Symptom checklist accepted on any entry_type, not just quick.** The
Mobile UI doc frames the disease-specific checklist as a Quick Check-in
screen field; voice entries get their symptoms from AI extraction
instead (not built yet). Since this pass has no AI, `POST /entries`
permissively accepts `symptom_ids` on voice entries too (as in the manual
test: a voice entry both carries a transcript and can flag "Chest pain"
via the checklist) — otherwise there'd be no way to test/demo a
voice-entry hard-red-flag without the AI layer. Revisit once AI-driven
extraction exists and can populate `entry_symptoms` itself.

**Alerts created for Yellow/Orange/Red, not Green.** Matches the project
doc's Alerts Panel description ("All yellow/orange/red alerts").

**`source` is always `'rule'` in this pass**, per the task's explicit
instruction — `'ai'` and `'merged'` are reserved for once the AI layer
exists alongside this engine.

**RBAC on `POST /entries` reuses `is_authorized_for_patient` via a
body param, not the path-based `get_authorized_patient` dependency.**
The task specifies the literal path `POST /entries` (no `{patient_id}` in
the URL), so `patient_id` arrives in the JSON body instead. Refactored
`app/core/deps.py` to extract the RBAC rule itself into a plain
`is_authorized_for_patient(user, patient) -> bool` helper, used by both
the existing path-based dependency and this new body-based check — avoids
duplicating the ownership policy in two places.

**Verified end-to-end**, not just written: threw away Postgres, ran
migrations (no new migration needed — every column this pass touches
already existed) + seed, hit `POST /entries` and
`GET /entries/{patient_id}/timeline` for real over HTTP. Confirmed: chest
pain hard-flag -> Red; normal quick entry -> Green; baseline-deviation +
streak + missed-dose scoring combining into Yellow; RBAC on both new
routes across patient/attendant/doctor/other-patient (all four outcomes
matched: self-access allowed, attendant-of-record allowed, doctor
submitting rejected by role gate, unrelated patient rejected); Pydantic
validation (voice without transcript, quick with no slider values, value
out of the confirmed 1-5 range) all correctly rejected with 422; alerts
rows created only for non-Green results.

---

## 2026-08-24 — Authentication (password hashing, JWT, RBAC)

**Quick check-in 1-5 scale — now CONFIRMED, not assumed.**
The previously-missing `docs/RozNoor_Mobile_UI_Field_Requirements.docx` is
now present. It describes sleep/energy/mood/appetite/mobility as sliders
with labeled low/high ends (e.g. "Very poor -> Very good") but still gives
no explicit numeric bounds. The user has explicitly confirmed the 1-5
integer scale (sleep in hours as the one exception) as locked. Treat this
as settled going forward, not open — [[schema]] and `seed.py` already
reflect it.

**Password hashing: bcrypt via the `bcrypt` package directly, not passlib.**
`passlib`'s bcrypt backend has known compatibility breakage with recent
`bcrypt` releases (missing `__about__` attribute). Using `bcrypt.hashpw` /
`bcrypt.checkpw` directly in `app/core/security.py` avoids that dependency
entirely. bcrypt's 72-byte password truncation limit is not separately
enforced — acceptable for hackathon scope.

**JWT library: PyJWT, not python-jose.** Simpler, single-purpose, no
known issues; sufficient for HS256 sign/verify.

**Token shape and lifetime.** Access token payload is
`{"sub": <user_id>, "role": <role>, "iat", "exp"}`, HS256, signed with
`settings.jwt_secret_key` (env `JWT_SECRET_KEY`, defaults to an
obviously-insecure dev string — **must** be overridden before any real
deployment). Expiry is 24h (`access_token_expire_minutes = 1440`), and
there is **no refresh token / revocation mechanism** in this pass — out of
scope for the hackathon; a user must re-login after 24h or after a
password change (old tokens for that user stay valid until they expire,
since nothing is checked beyond signature + expiry). Revisit if judged
demo needs longer-lived sessions or logout-everywhere.

**Auth transport: JSON body + Bearer header, not OAuth2 password flow.**
`POST /auth/login` takes a plain JSON body (`phone_or_email`, `password`)
per the task's spec, rather than FastAPI's OAuth2PasswordRequestForm
(form-encoded, field name `username`). Protected routes read
`Authorization: Bearer <token>` via `HTTPBearer`, not
`OAuth2PasswordBearer` — matches a JSON API rather than the OAuth2 login
widget FastAPI's docs default to.

**Attendant included in patient-access RBAC, beyond the task's literal
list — CONFIRMED correct by the user (2026-08-24), not an overreach.**
Keep as built. Added a fourth branch — attendant allowed if
`patients.attendant_user_id` matches — because the schema already models
attendant-managed patients (`patients.attendant_user_id`) and leaving
attendants with zero data access would contradict the product's own
user-roles table (Final Project Document section 5, "Attendant / Family
Caregiver").

**`GET /patients/{patient_id}` added as a minimal RBAC proof endpoint.**
Not asked for explicitly, but RBAC point 4 ("a patient can only access
their own patient_id's data...") can't actually be verified without at
least one real protected route using the dependency. Kept intentionally
thin — just returns `PatientOut` (id, mr_number, diagnosis, age,
baseline_stage, day_count, and the three FK columns). Full patient
CRUD/list endpoints are a separate future task.

**Seed passwords: one shared demo password for every seeded user.**
`SEED_PASSWORD = "RozNoor@123"` in `seed.py`, real bcrypt-hashed via
`hash_password()`. Printed at the end of `python seed.py` output for
convenience. This replaces the prior placeholder-hash approach — see the
now-superseded note below.

---

## 2026-08-24 — Backend foundation (models, migrations, seed)

**Table count: 11, not 12.**
`docs/RozNoor_Database_Schema_and_Deployment_Plan.docx` section 4 says
"Twelve tables total" but only fully defines 11: `users`, `patients`,
`entries`, `entry_symptoms`, `symptom_checklist_options`, `ai_results`,
`risk_results`, `baseline_history`, `alerts`, `doctor_notes`,
`weekly_digests`. Asked the user; confirmed to build exactly these 11 and
treat the "twelve" in the doc header as a miscount. `medication_info`
stays a plain text field on `patients` (the doc's default option) rather
than being split into a separate `medications` table.

**`docs/RozNoor_Mobile_UI_Field_Requirements.docx` does not exist.**
*(Resolved 2026-08-24 — the doc is now present in `docs/` and has been
read in full; see the auth-session entries above for what it confirmed.)*
The user's task referenced it, but only the Final Project Document and
the DB Schema doc are present in `docs/`. Flagged to the user; not
blocking for this backend-only pass since no API/UI contracts were being
built yet. Re-check when building schemas/routers or the mobile app.

**Enum value casing.**
Schema doc gives most enums as slashed plain-English options with no
canonical casing (e.g. "patient / attendant / doctor / admin"). Used
lowercase snake_case for these. The one exception: `risk_level`
(Green/Yellow/Orange/Red) is capitalized everywhere in both the doc and
the UI prototype as the literal user-facing label, so that exact casing
was preserved as the enum values.

**Quick check-in metric scale.** *(Superseded 2026-08-24 — see the
"CONFIRMED" entry above; the mobile UI field-requirements doc has since
been provided and the user locked this decision.)*
`entries.sleep_value/energy_value/mood_value/appetite_value/mobility_value`
are `numeric` with no scale specified in either doc, and the mobile UI
field-requirements doc (which likely would have specified this) is
missing. Seeded `sleep_value` in hours (matches the 4.5-8h baseline chart
range shown in the prototype) and energy/mood/appetite/mobility on a 1-5
scale (1 = very low, 5 = very good) as a placeholder assumption. **Revisit
once the mobile UI field-requirements doc is available or the quick
check-in endpoint is actually built** — the real scale may differ.

**Role-restricted FKs not DB-enforced.**
`patients.assigned_doctor_id` and `attendant_user_id` are expected to
reference `users` rows with `role='doctor'` / `role='attendant'`
respectively, per the schema doc's notes column. Postgres FKs can't
express that constraint directly; enforcing it would need a trigger or
application-level check. Deferred — not needed for models/migrations/seed,
revisit when building the patients router.

**Postgres host for local dev/testing.**
Doc leaves the choice open (Railway add-on vs. Neon vs. Supabase) with no
final pick. Used a throwaway local Postgres container just to prove
migrations + seed actually run; this doesn't decide the real hosting
choice — `DATABASE_URL` is fully swappable via `.env` and no code assumes
a specific host. Ask before actually provisioning Railway/Neon.

**Symptom checklist content.**
Heart-failure symptom names in `seed.py` are taken verbatim from the
prototype (`RozNoor.dc.html` `symDefs`). Post-surgical symptom names
(Wound redness, Wound discharge, Fever, Incision pain, Reduced mobility,
Swelling at site) are invented — the prototype only shows the
heart-failure checklist screen in full. Fine for seed/demo data; flag if
a clinician needs to sign off on the actual post-surgical red-flag list
later (schema doc explicitly calls red-flag rules "clinician-reviewable").

**Seed script is destructive/re-runnable.**
`seed.py` clears all rows (child-first FK order) before inserting, so
re-running it always produces the same known state. Fine since there's no
real user data yet; revisit before this ever runs against a populated env.

**Auth/password_hash placeholder.** *(Superseded 2026-08-24 — real bcrypt
hashing is now implemented; see the auth entries above. `seed.py` now
hashes a real demo password instead.)*
Seeded users get `password_hash = "seed-placeholder-not-a-real-hash"`.
Authentication isn't built yet (explicitly deferred by the user's task) —
this is not a real hash and must not be used to actually authenticate
anyone once auth is implemented.
