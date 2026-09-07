# Pending real-device tests

Session-to-session handoff for real-hardware verification that's mid-flight.
Read this FIRST if you're picking up real-device testing — it exists so you
don't have to re-derive state from `decisions-log.md`'s full narrative every
time. Update or delete this file as items get resolved; it's a working
checklist, not a permanent record (the permanent record is
[[decisions-log]]/[[progress]]).

---

## 0. Manual end-to-end test against the REAL production backend (Railway) — BLOCKED on a "Could not reach RozNoor" report; manifest/network-config investigated and cleared, root cause still open

**First real attempt already made and failed**: the user ran the installed
release APK and got `"Could not reach RozNoor. Check your connection & try
again."` even though the same phone's own mobile Chrome loads
`https://roznoor-production.up.railway.app/docs` fine. A follow-up session
(2026-09-02, later still — see [[decisions-log]]) investigated
`AndroidManifest.xml` and `network_security_config.xml` in full and found
**both correctly configured, not the cause** — INTERNET permission present
and correctly placed in the release manifest; the one
`network_security_config.xml` in the repo is debug-only-scoped and doesn't
affect the release build at all, which correctly uses Android's default
(HTTPS-permitted, cleartext-blocked) policy, exactly right for an
`https://` backend. Went further and pulled the actual installed APK off
the device (`strings`/`aapt dump badging`: confirmed the real production
URL is baked in, INTERNET permission compiled in) and ran OS-level
diagnostics on the same physical device (`neo7U2401003561`): raw TCP:443
to the backend succeeds, DNS resolves, TLS handshake completes against a
valid non-expired Let's Encrypt chain, and the app's UID has zero
Doze/Data-Saver/firewall/VPN restriction. **Nothing found broken anywhere
checked.** No code/config change was made (nothing to fix); the release
APK was rebuilt and reinstalled anyway
(`--dart-define=ROZNOOR_API_BASE_URL=https://roznoor-production.up.railway.app`,
confirmed fresh via `adb shell dumpsys package`:
`firstInstallTime`/`lastUpdateTime` `2026-09-02 12:15:18`) — functionally
identical to what was already installed, purely to hand back a
guaranteed-current build.

**What's ready, as of 2026-09-02**: backend live and seeded at
`https://roznoor-production.up.railway.app`; `web_app` live at
`https://roznoor.up.railway.app` (already manually verified — a real
patient login + a voice/check-in entry correctly triggered a hard-flag Red
result); the Flutter release APK rebuilt with
`--dart-define=ROZNOOR_API_BASE_URL=https://roznoor-production.up.railway.app`
baked in (confirmed via `strings` on the built APK, twice now across two
sessions — the production URL is present, the `localhost:8000` default is
completely absent) and freshly reinstalled on the real device
(`neo7U2401003561`, Sparx Neo 7 Ultra).

**What's genuinely still open — retry needed, with better diagnostics this
time**: the "Could not reach RozNoor" symptom itself is **not yet
explained**, only the two most obvious suspects (manifest, network
security config) have been ruled out. Next attempt should capture `adb
logcat` (running live, not started after the fact) during the actual
failed request, and note exactly which WiFi/mobile-data network the phone
is on at the time — that's the one variable the investigating session
couldn't reproduce or check (it only had access to a different WiFi
network). If it fails again, read the real logcat output / DioException
detail before forming a new theory, per this project's own repeated
"verify before fixing" lesson (see [[decisions-log]] — Postgres port
confusion, Brave-browser incident, and now this entry). If it succeeds
this time, update this item and [[progress]]/[[decisions-log]] with the
real result, then continue to Voice Diary, the chest-pain hard-flag check,
and the doctor dashboard.

---

## 1. Acoustic-analysis audio upload (`POST /entries/{id}/audio`) — ✅ RESOLVED 2026-09-01

**Resolved for real, on real hardware, with far more than the required
margin.** Full narrative in [[decisions-log]] (2026-09-01 entry — note
that entry is primarily about a different finding, the missing-API-key
symptom-extraction gap, but the same session's voice-testing incidentally
produced these audio-upload confirmations as a side effect).

**8 independent real successes this session** (entries 68-75, phone
`neo7U2401003561` over LAN WiFi, backend LAN IP unchanged at
`192.168.100.58`), each independently confirmed three ways — not just the
Result screen:
1. Backend log: real `POST /entries/{id}/audio ... 200 OK` for all 8.
2. Direct Postgres `SELECT`: `audio_file_path` non-empty and
   `acoustic_features` non-null on all 8, with genuinely varying values
   per entry (different pitch/energy/duration numbers) — proof each one
   is freshly computed from a real recording, not cached/stale/identical
   placeholder data.
3. Filesystem: spot-checked 3 of the 8 files exist on disk at their
   recorded `audio_file_path`, each ~100KB, timestamps matching their
   submission times.

Combined with entry 43 from the 2026-08-28 session, that's **9 total
real successes across two sessions with zero failures** — well past the
"2-3 repeat confirmations to rule out intermittency" bar this item was
waiting on. The two root-cause fixes from 2026-08-28 (the
`record_platform_interface` override, and the `canAnalyze`/`_listening`
button-gating fix) are holding with no regression.

**Genuinely closed — no further confirmations needed for this item.**

<details>
<summary>Original in-progress writeup (2026-08-28), kept for history</summary>

**Full investigation trail**: [[decisions-log]], 2026-08-28 entry (and the
2026-08-27 entry above it for the earlier label-bug/mic-contention history).

### Confirmed working, don't re-litigate
- Voice recording itself (speech-to-text transcript + the sequenced 6-second
  follow-up audio sample) — device-verified since 2026-08-27.
- The mic-contention fix (sequenced capture instead of concurrent) — still
  holding, no regression.
- **Two real root causes of the silent upload failure found and fixed this
  session** (2026-08-28), both in `mobile_app/`:
  1. `pubspec.yaml`'s `dependency_overrides` was forcing
     `record_platform_interface` down to a version below what
     `record_android` actually needs — a leftover, too-broad fix from the
     2026-08-27 Linux-build workaround. Fixed by overriding `record_linux`
     to `1.3.1` instead, which resolves the interface up to 1.6.0 and
     satisfies both platforms. This eliminated a real crash
     (`Bad state: Cannot add new events after calling close`) but was
     **not** the actual reason uploads failed — just a separate real bug
     found along the way.
  2. **The actual cause**: `canAnalyze` (gating the "Save & analyse"
     button) never checked `_listening` — so the button was tappable
     while the user was still actively speaking, before the follow-up
     audio capture had even started. Fixed by adding `&& !_listening`.
  3. Also added: `debugPrint` diagnostics in `AudioRecorderService.start()`/
     `.stop()` and around `_captureFollowUpAudioSampleOnce()`/`_analyze()`
     (previously silent — same anti-pattern as the original `attachAudio()`
     bug). These are genuinely useful diagnostics, not just scaffolding —
     leave them in.
- **One full end-to-end success, verified for real** (not just "the UI
  didn't error"): entry 43 — backend log showed a real
  `POST /entries/43/audio HTTP/1.1" 200 OK`; DB query confirmed a real
  `audio_file_path` and fully populated `acoustic_features`; the file was
  confirmed to exist on disk at 100,261 bytes.

### NOT yet confirmed — this is the actual open item
Per the task's own explicit instruction: **do not call this resolved on one
success alone.** The earlier failures looked intermittent across sessions
(worked in some UI senses, silently failed underneath), which is worse for
a live demo than a consistent bug. **1 of 2-3 required repeat confirmations
is done (entry 43). Need 2 more**, each independently checked in the DB —
not just "the Result screen showed a risk level," since that shows
regardless of whether audio ever attached.

The session was paused here because the user is traveling with only mobile
data — the phone cannot reach the dev machine's LAN backend at all right
now. This is an environment limitation, not a new failure — don't read the
pause itself as a regression or a reason to doubt the fix.

### Exact resume steps
**On the dev machine (this environment), before asking for a test:**
1. Check `roznoor-pg` is running: `docker ps --format '{{.Names}}\t{{.Status}}'
   | grep roznoor` — if stopped, `docker start roznoor-pg`.
2. Start the backend bound to the LAN interface, from `Backend/`:
   `.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload`
   (background it, log to a file you can tail).
3. Confirm the dev machine's LAN IP hasn't changed (DHCP-assigned, can
   drift): `hostname -I` — as of this session it was `192.168.100.58`. If
   it changed, the phone needs a fresh build with the new
   `--dart-define=ROZNOOR_API_BASE_URL=http://<new-ip>:8000` (the currently
   installed APK already has the last-known-good IP baked in at build time
   — it's NOT runtime-configurable from the phone, see
   `mobile_app/lib/core/app_config.dart`).
4. Confirm the phone via `adb devices -l` — same phone as every prior pass
   (`neo7U2401003561`, Sparx Neo 7 Ultra), connected via USB.
5. Start live log capture: `adb logcat -c` then
   `adb logcat "flutter:V" "*:S" > <some log file>` in the background —
   this is how `debugPrint` output becomes visible (the app's own
   `attachAudio failed (...)`/`AudioRecorderService`/`_captureFollowUp...`
   diagnostics all surface here with tag `flutter`).
6. Verify reachability before involving the user:
   `curl http://192.168.100.58:8000/health` (or whatever the current LAN
   IP is) — should return `{"status":"ok",...}`.

**What to ask the user to do on the phone, once they're back on the same
WiFi as the dev machine:**
1. Force-close and reopen the RozNoor app (not strictly required if no new
   APK was installed since their last test, but cheap and removes doubt).
2. Voice Diary → record a short entry → wait for the transcript → **wait
   for "Capturing voice sample for analysis…" to fully clear and the
   button to become tappable** (this is the actual fix — the button is now
   correctly disabled until this finishes) → tap "Save & analyse".
3. Report back once submitted.

**Then, in this environment**: check the backend log for a real
`POST /entries/{id}/audio ... 200 OK` line, and query the DB directly
(don't trust the Result screen alone):
```sql
SELECT e.id, e.entry_type, e.timestamp, e.audio_file_path, ar.acoustic_features, rr.risk_level, rr.source
FROM entries e
LEFT JOIN ai_results ar ON ar.entry_id = e.id
LEFT JOIN risk_results rr ON rr.entry_id = e.id
ORDER BY e.timestamp DESC LIMIT 3;
```
Confirm `audio_file_path` is non-empty and `acoustic_features` is non-null
on the newest entry. Repeat for a 3rd confirmation. Once 2 more clean
successes are in hand (3 total), write the final close-out into
[[decisions-log]] and flip the [[progress]] checklist item to genuinely
done — not before.

**If any of the 2 remaining confirmations fails**: do not guess again.
Same method as this session — read the exact `adb logcat` output and the
backend log for that specific attempt, and reason from what's actually
printed, not from a new theory. If it's a NEW failure mode (not the two
already fixed), it needs its own live-reproduction cycle the same way
these did.

</details>

---

## 2. Other open real-device checklist items (from [[progress]], 2026-08-27 pass)

Not touched this session — listed here only so they're not lost, since they
were already open before this session started:
- **Paper/Nocturne theme toggle** — not yet device-tested on a real phone
  (only verified on an isolated Linux-desktop Xvfb build so far, per
  [[progress]]'s 2026-08-27 entry). Not blocking the audio-upload work,
  just still open.
- **Quick check-in regression check** — not re-tested since the 2026-08-27
  mic-contention/label fixes landed. Low risk (nothing in that pass touched
  the quick check-in path), but not re-confirmed live either.

Neither of these needs the same live-log-watching setup as the audio-upload
item — a normal device test (submit, check the Result/Timeline screens,
spot-check the DB if anything looks off) is enough.

## 3. Web app real-microphone testing — ✅ RESOLVED 2026-09-01

**Resolved for real, with a real browser-compatibility finding along the
way.** Full narrative in [[decisions-log]].

**A second false start, diagnosed properly rather than assumed**: the
first retry attempt this session hit `Recognition error: network` again —
looked like a repeat of the 2026-08-29 connectivity issue, but this time
the user confirmed Google's own voice search worked fine on the same
machine, ruling out a real connectivity problem. Root cause: **the
browser was Brave, not Chrome.** Brave deliberately blocks/strips the
underlying Google speech-recognition service as part of its privacy
model (a real, separate mechanism from Shields, and not something Shields
alone reliably fixes) — this exactly matches `VoiceDiaryScreen.jsx`'s own
doc comment, which has always scoped this feature to "Chrome/Edge only";
Brave was never a tested or supported browser. **Not an app bug** — the
same code worked immediately once the user switched to real Google
Chrome.

**Full pipeline confirmed real, end-to-end, in real Chrome with real
internet** (entry 76, patient 8): real `SpeechRecognition` transcript
("hello I am feeling not well I have chest pain and breathlessness"),
real AI-merged symptom extraction (`["Chest pain", "Breathlessness",
"general malaise: feeling unwell"]`, `source: "merged"`), correct hard
red-flag (`risk_level: Red`, correct reasoning), and a real
`MediaRecorder`-captured `.webm` acoustic sample —
`audio_storage/8/entry76_9d27ec99.webm`, 96,896 bytes, confirmed on disk,
correctly decoded (`acoustic_features` populated). Verified via the live
backend log (`POST /entries → 201`, `POST /entries/76/audio → 200`) and a
direct Postgres `SELECT` — not just the Result screen.

**This is the first-ever real confirmation of the web app's full Voice
Diary pipeline** (speech recognition → AI-merged extraction → rule engine
→ acoustic capture) on real hardware/internet — previously only verified
via the typed-text fallback.

<details>
<summary>Original writeup (2026-08-29), kept for history</summary>

**Update, same day, real-user attempt**: the user tried this for real (own
laptop, own microphone) and hit `Recognition error: network` — CONFIRMED
by the user as their own limited/mobile-data connectivity, not an app bug
(they independently tested Google's own voice search/demo and got the
same failure — see [[decisions-log]] for the full write-up). This is the
expected failure mode for Chrome's cloud-based `SpeechRecognition` without
reachable internet, exactly the limitation already flagged in
`VoiceDiaryScreen.jsx`'s own doc comment. **Still not resolved — this
attempt does NOT count as a successful confirmation**, it just rules out
"the code is broken" as the explanation. Needs a retry once the user (or
whoever picks this up) has a normal, working internet connection.

**Update, same day, real-user attempt**: the user tried this for real (own
laptop, own microphone) and hit `Recognition error: network` — CONFIRMED
by the user as their own limited/mobile-data connectivity, not an app bug
(they independently tested Google's own voice search/demo and got the
same failure — see [[decisions-log]] for the full write-up). This is the
expected failure mode for Chrome's cloud-based `SpeechRecognition` without
reachable internet, exactly the limitation already flagged in
`VoiceDiaryScreen.jsx`'s own doc comment. **Still not resolved — this
attempt does NOT count as a successful confirmation**, it just rules out
"the code is broken" as the explanation. Needs a retry once the user (or
whoever picks this up) has a normal, working internet connection.

Original scope, unchanged below:

The React web app's Voice Diary (`web_app/src/screens/patient/VoiceDiaryScreen.jsx`)
was built and verified via its typed-text fallback only — no audio input
hardware in the sandboxed browser environment used for this session's
verification. See [[progress]] and [[decisions-log]] (2026-08-29, "React
web app built" entry) for the full build/verification narrative. Two
things specifically need a real browser with a real microphone:
1. **Speech recognition itself** (`SpeechRecognition`/
   `webkitSpeechRecognition`) — works in Chrome/Edge, not Firefox, needs
   HTTPS in production (localhost is exempted, which is what this
   session's `npm run dev` verification relied on).
2. **The follow-up acoustic-analysis sample** (`MediaRecorder` via
   `getUserMedia`, sequenced after recognition ends) — uploads via
   `POST /entries/{id}/audio` exactly like the mobile app's `.m4a`
   recordings, just as `audio/webm`. This endpoint already accepts webm
   (see [[api-contracts]]), so the upload path itself is not new/unproven
   backend-side — what's unverified is only the CLIENT side actually
   capturing real audio in a real browser.

**To resume**: open `http://localhost:5173` (or wherever `web_app` is
served) in an actual desktop/laptop Chrome browser with a working
microphone — no phone needed, this is a browser-only gap, unrelated to
either of the phone-based items above. Log in as a seeded patient (e.g.
`zubaida.b@roznoor.care` / `RozNoor@123`), open Voice Diary, tap the mic,
say something, stop, wait for "Capturing voice sample for analysis…" to
clear, then "Save & analyse this entry". Check the backend log for
`POST /entries/{id}/audio ... 200 OK` and query the DB the same way item 1
above does (`audio_file_path` non-empty, `acoustic_features` non-null) to
confirm it's real, not just that the UI didn't error.

</details>

## 4. Doctor role real-device testing — ✅ RESOLVED 2026-09-01

**Resolved for real on the actual phone.** Full narrative in
[[decisions-log]]. Rebuilt (`flutter build apk --debug
--dart-define=ROZNOOR_API_BASE_URL=http://192.168.100.58:8000`) and
reinstalled (`adb install -r`) fresh this session, then driven live on
`neo7U2401003561`:
- Logged in as **Dr. Ayesha Farooq** (`a.farooq@civilhosp.pk`, id 23) —
  roster/alerts/patient-detail all rendered real data; marked 5 real
  alerts reviewed through the UI (ids 16, 10, 13, 11, 15), all confirmed
  `reviewed: true` via a direct Postgres `SELECT`; added a real note
  (patient 8, id 11), confirmed persisted via `SELECT`.
- **Account-switch scenario, the exact one that caught a real bug in the
  Xvfb pass**: logged out, logged in as **Dr. Hamza Iqbal**
  (`h.iqbal@civilhosp.pk`, id 24) — confirmed via the live backend log
  that every subsequent call switched to `/doctors/24/...` with zero
  stale `/doctors/23/...` calls afterward; added a second real note
  (patient 11, id 12) — confirmed via a direct Postgres `SELECT` that
  both the `doctor_id` (24) and `patient_id` (11, genuinely on Dr.
  Hamza's own roster per `patients.assigned_doctor_id`) were correct, not
  a cross-doctor leak.
- **No stale-data bug on real hardware** — the `root_router.dart` fix
  from the earlier Xvfb pass holds up on the actual device too.

---

## Do not start Phase 2 (doctor role) — LIFTED 2026-08-29 for the Flutter build itself, item 1 still fully standing

**2026-08-29 update**: the user was explicitly asked whether to honor this
hold or proceed, given a same-session task brief asking for the doctor
role now. **The user explicitly chose to proceed** — see [[decisions-log]]
for the full conflict writeup. This lifts the hold only for what was
actually done (building/verifying the doctor role via Xvfb + direct API
calls, no phone involved) — it does NOT touch, resolve, or shortcut item 1
above, which still needs its 2 remaining phone-based confirmations before
being called genuinely done, and does NOT retroactively mean future
sessions should assume this hold is gone by default — if a future session
hits a similar conflict, surface it again rather than assuming this
override still applies.

Original text, kept for context: per the user's explicit instruction
(prior session, 2026-08-28): don't start Phase 2 until item 1 above is
fully resolved and re-verified on real hardware with 2 more clean
confirmations, not just one session's success. That underlying concern
(item 1 unresolved) is still just as true today as it was when written.
