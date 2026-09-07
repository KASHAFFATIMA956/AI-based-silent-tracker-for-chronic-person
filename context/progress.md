# Progress

## Chest-pain first-aid guidance panel added (2026-09-07, latest) — PROTOTYPE, not clinically reviewed, needs real sign-off before non-demo use

Added a fixed, hand-authored first-aid guidance panel to the Result screen on both
`mobile_app` and `web_app`, shown only when an entry's result is Red AND its
`symptom_names` includes the "Chest pain" hard-flag symptom (the existing
`app/services/rules.py` chest-pain hard flag). **The rule engine itself is completely
unchanged** — this is a display-layer-only addition, no backend/schema/scoring changes.
Full narrative, including the exact AHA source pages confirmed via a real web search
before any content was written, in [[decisions-log]].

- **What was built**: a small explicit mapping (`mobile_app/lib/core/
  first_aid_guidance.dart`, mirrored in `web_app/src/core/firstAidGuidance.js`), scoped
  to exactly one condition (suspected heart attack), containing: a primary "call
  emergency services immediately" instruction (always shown, most prominent); a
  4-item contraindication checklist (aspirin allergy, blood thinners, bleeding
  disorder, adult-only) that must be actively confirmed (all four checked) before any
  aspirin-specific guidance is revealed; secondary aspirin guidance, visually and
  structurally subordinate to the call-for-help instruction; a suppressed-state
  fallback (call-for-help + "tell responders about symptoms/allergies/medications")
  shown whenever any box is unconfirmed or left "not sure"; and an always-visible "This
  is general guidance, not personal medical advice" disclaimer. New widget/component:
  `mobile_app/lib/widgets/chest_pain_first_aid_panel.dart` /
  `web_app/src/components/ChestPainFirstAidPanel.jsx`, both wired into their platform's
  `ResultScreen` with a 2-line detection check.
- **Content sourcing**: paraphrased (not verbatim) from two real, confirmed-to-exist
  American Heart Association pages — "Warning Signs of a Heart Attack" and the 2024
  AHA/American Red Cross Guidelines for First Aid, Part 8. Both citations are shown
  in-app in small print, not just recorded in context files.
- **Verified for real**: `flutter analyze` and `npm run build`/`npm run lint` (web) all
  clean — zero new issues from any file this pass touched. **Not verified against a
  real running backend/live chest-pain entry this session** (no backend/DB running in
  this environment) — the detection condition was verified by reading the actual rule
  engine code and documented API response shape, not by an end-to-end submission.
- **PROTOTYPE, requires real clinical sign-off before any real-world (non-demo) use.**
  See the new entry in [[pre-deployment-checklist]] for exactly what that review would
  need to cover — this is explicitly flagged as more safety-sensitive than any other
  part of this app (active medication guidance, not passive risk flagging) and must not
  be presented as production-ready medical advice.

## Direct messaging added (2026-09-07, direct-messaging session, latest) — patient/attendant <-> assigned-doctor chat, both platforms, RBAC-tested including cross-patient read blocking

Added a `messages` table, RBAC-protected `POST`/`GET /patients/{patient_id}/messages`,
and a shared chat screen on both `mobile_app` and `web_app`. Polling (12s), not
websockets — none exist in this backend. Text-only: no read-receipts UI, no typing
indicators, no attachments (all explicitly out of scope). Full narrative in
[[decisions-log]].

- **Schema**: `alembic/versions/97a9fb958383_add_messages_table.py` — new `messages`
  table (`patient_id`, `sender_user_id`, `sender_role`, `content`, `created_at`,
  `read_at`), new `message_sender_role` Postgres enum (patient/attendant/doctor —
  deliberately no `admin` value). No existing table touched.
- **Backend RBAC**: reads reuse the existing `get_authorized_patient` dependency
  unchanged (admin/assigned-doctor/self-patient/linked-attendant — same rule as the
  timeline endpoint). Writes use a new, narrower `is_authorized_to_send_message`
  (`app/core/deps.py`) — **admin is deliberately blocked from sending** (no valid
  `sender_role` to record it under), the one asymmetry from every other RBAC check in
  this app. `app/routers/messages.py` is its own file (same `/patients` prefix as
  `patients.py`) and returns the thread **oldest-first** — the one deliberate
  newest-first exception in this app, since a chat reads top-to-bottom.
- **Frontend**: one shared, role-agnostic chat screen per platform
  (`mobile_app/lib/screens/messages_screen.dart`, `web_app/src/screens/MessagesScreen.jsx`)
  at the top level of each `screens/` folder, parameterized by `patientId`/`title`.
  Patient entry point: a new "Messages" nav card/sidebar item (title = assigned
  doctor's name). Doctor entry point: a new button on the patient detail screen
  (title = the patient's name). Chat-bubble UI, own messages right-aligned (derived
  from `sender_user_id == the signed-in user's own id`), timestamps shown.
- **Polling lifecycle, platform-appropriate on each side**: mobile reaches this screen
  via `Navigator.push` (deliberately NOT a `PatientShell`/`DoctorShell` `IndexedStack`
  tab, which would keep the poll timer running invisibly after switching tabs) so
  `dispose()` genuinely cancels the timer on leaving; web's plain React Router route
  unmounts on navigation automatically, so a `useEffect` cleanup already provides the
  same guarantee with no equivalent navigation-pattern decision needed.
- **Verified for real, not just written**: 12 real-HTTP RBAC checks against real seeded
  accounts, all correct on the first run — patient/attendant/assigned-doctor can send;
  an unassigned doctor, an unrelated patient, AND admin all correctly get `403` on
  send; **the specific check the task asked to confirm** — an unrelated patient reading
  another patient's thread gets a real `403`, not someone else's messages; admin CAN
  read any thread (read access isn't narrowed the way write access is); oldest-first
  ordering confirmed; unauthenticated/nonexistent-patient/empty-content all correct.
  `flutter analyze` clean (only pre-existing style lints); `npm run build` clean;
  `npm run lint` clean except one new harmless `set-state-in-effect` info warning on a
  standard fetch-on-mount pattern (read, understood, not a bug — see [[decisions-log]]).
- **Explicit follow-up, not done this pass**: real-time push (websockets/SSE) is a
  possible future upgrade, not built here per the task's own instruction. Tracked
  alongside this project's other open items below.

## Optional blood pressure / blood sugar fields added (2026-09-07, final session) — persisted and displayed, deliberately NOT wired into risk scoring

Added `entries.systolic_bp`/`diastolic_bp`/`blood_sugar_mg_dl` (nullable
integers, following the `weight_value` precedent column-for-column) end
to end: schema migration, backend persistence, Quick Check-in UI on both
platforms, and display on the doctor's patient-detail view and the
patient's own Timeline. Full narrative in [[decisions-log]].

- **Migration**: `alembic/versions/95fc7e1824e7_add_entries_bp_and_blood_sugar.py`,
  applied cleanly to the dev Postgres; `python seed.py` re-ran with zero
  errors against the new schema.
- **Backend**: `EntryCreate`/`EntryOut` gained the three optional fields
  (bounds: systolic 40-300, diastolic 20-200, blood sugar 20-800 mg/dL —
  sanity checks, not clinical ranges). **Deliberately NOT passed into
  `app/services/rules.py`** — persisted/returned only, per the task's
  explicit scope.
- **Frontend**: Quick Check-in on both `mobile_app` and `web_app` gained a
  "Blood pressure (optional)" systolic/diastolic pair and a "Blood sugar
  (optional, mg/dL)" field, styled to match the existing optional-weight
  field (muted helper text/placeholders, no required marker). Voice Diary
  on both platforms confirmed to have no equivalent manual-entry step
  (same as `weight_value`) — the new fields are reachable from there only
  via the existing "Type instead — full check-in" link, same as before.
- **Display**: both the patient's own Timeline and the doctor's
  patient-detail view show "BP n/n" and "Sugar n mg/dL" whenever present,
  mirroring the existing Sleep/Energy/Weight display convention exactly.
- **Verified for real, not just written**: a real quick entry with all
  three fields set persisted correctly (confirmed via a direct Postgres
  `SELECT`); a second entry without them saved with all three `null`;
  both produced byte-identical `risk_result`s, confirming zero effect on
  scoring; a separate chest-pain entry still correctly hard-flagged `Red`,
  confirming the existing rule engine is unmodified; an out-of-range value
  correctly `422`s. `flutter analyze` clean (only pre-existing style
  lints); `npm run build` clean.
- **Explicit follow-up, tracked below**: wiring these three fields into
  the rule engine's actual scoring needs a separate pass with real
  clinical threshold review — not done this session, by design.

## Adaptive-icon clipping risk RESOLVED (2026-09-07, later still) — new inset foreground verified, regenerated, rebuilt

Follow-up to the entry immediately below, which flagged
`app_icon.png`/`app_icon_foreground.png` as byte-identical (no inset,
clipping risk). Full narrative in [[decisions-log]].

- **Only `app_icon_foreground.png` was actually replaced this session** —
  `app_icon.png`'s hash/mtime are byte-for-byte identical to last
  session's, confirmed by direct comparison, not assumed. This is the
  correct fix shape: the master doesn't need an inset (not adaptive-mask
  cropped), only the foreground did.
- **Inset confirmed both visually and numerically**: content now occupies
  43.3%×56.8% of the 1024×1024 canvas, giving a worst-case 21.6% margin —
  comfortably past the ~17% minimum Android's adaptive-icon safe zone
  requires. **Went further than a bounding-box number**: composited the
  new foreground over the real adaptive-icon background color and applied
  a full circular mask (the strictest common launcher mask shape) — the
  entire artwork, including the sun-rays and leaf tip that were the
  original concern, sits fully inside with visible margin. **The clipping
  risk is genuinely resolved**, not just measured.
- **Regenerated via the same existing command** (`dart run
  flutter_launcher_icons`) — confirmed via before/after file sizes (not
  just timestamps) that only the adaptive-icon foreground files changed
  size, while every legacy-icon/iOS file stayed byte-identical since its
  source didn't change — precise confirmation the tool did exactly the
  right thing.
- **Rebuilt the release APK**, re-checked for a connected device first
  (none found, same as before) — confirmed via `aapt`/`strings` that label
  and prod URL are intact, and confirmed by unzipping the built APK itself
  that the new inset artwork is what's actually packed into this binary.
- **On-device visual confirmation is still pending** — no physical device
  connected this session either.

## Logo swap: new source files applied, icons regenerated for real (2026-09-07, later same day)

New logo (heart + sun + person + medical cross + leaf, green/teal
gradients) dropped in at the existing three paths, replacing the old teal
pulse concept. Full narrative in [[decisions-log]].

- **Verified the source files were genuinely replaced**: `git diff`/
  `sha256sum` confirmed all three (`mobile_app/assets/icon/app_icon.png`,
  `app_icon_foreground.png`, `web_app/public/favicon.svg`) differ from
  their previously-committed versions, not just touched/re-saved
  identically.
- **Dimension check passed**: both new PNGs are `1024x1024` RGBA — square,
  full master resolution. No stop condition triggered.
- **One real observation flagged, not fixed (out of this task's scope)**:
  `app_icon.png` and `app_icon_foreground.png` are byte-identical — the
  adaptive-icon foreground no longer has its own separately-inset
  transparent variant the way the 2026-08-27 icon did, and the new
  artwork's sun-rays/leaf tip sit close to the canvas edge, risking
  cropping by a real Android adaptive-icon mask. Needs a look on a real
  launcher; not something this pass should redesign unprompted.
- **Regenerated via the project's own existing command** (`dart run
  flutter_launcher_icons`, found in [[conventions]]/[[decisions-log]], not
  guessed) — confirmed via before/after `stat` timestamps that every
  Android `mipmap-*`/`drawable-*` file and all 21 iOS `AppIcon.appiconset`
  files were genuinely rewritten (new mtimes, new sizes), and by rendering
  the actual generated files (not the source) that they show the new
  artwork correctly.
- **`favicon.svg`**: verified well-formed SVG, `index.html`'s `<link>`
  still points at the same filename/path — no regeneration needed for a
  direct file swap.
- **Rebuilt both to confirm, no stale-cache surprises**: web build's
  `dist/favicon.svg` is byte-identical to the new source; the mobile
  release APK was rebuilt with the same production dart-define, and the
  new icon was confirmed actually packed into the built binary by
  unzipping the APK itself and rendering the resource directly (not
  trusted from the source tree, since AAPT2 recompresses PNGs at build
  time).
- **No physical device connected this session** — on-device visual
  confirmation of the new icon on a real launcher is still pending, same
  gap as the rebrand entry below.

## Display-name rebrand to "RozNoor" (2026-09-07) — Android label + iOS display name fixed; icon/favicon confirmed already correct; both platforms rebuilt to confirm

Client-side branding only, no backend/Railway changes. Full narrative in
[[decisions-log]].

- **Android**: `AndroidManifest.xml`'s `android:label` was the raw package
  name `"roznoor_app"` — now `"RozNoor"`. Confirmed baked into a real
  release build via `aapt dump badging` (`application-label='RozNoor'`
  across every locale, `application: label='RozNoor'`).
- **iOS**: `Info.plist`'s `CFBundleDisplayName` was `"Roznoor App"` — now
  `"RozNoor"`. (`CFBundleName` intentionally left as the internal
  `roznoor_app` identifier — not user-visible, same convention as the Dart
  package name.)
- **`pubspec.yaml`'s `name` field — deliberately not touched**: not a
  display-facing field in Flutter (it's the Dart package id, used in every
  `lib/` import); renaming it was never actually called for.
- **Icon**: confirmed already fully and correctly applied — every Android
  mipmap density + the full iOS `AppIcon.appiconset` already exist from the
  2026-08-27 icon-generation pass, already real-device-verified. Nothing
  regenerated, no new icon designed.
- **Web**: `index.html`'s `<title>` was already `"RozNoor"`; the favicon
  (`public/favicon.svg`) was already a teal pulse/heartbeat glyph in the
  same brand color, added in the 2026-08-29 favicon-404 fix — left as-is
  rather than replaced with a lower-fidelity raster export of the mobile
  icon. No PWA `manifest.json` exists in `web_app/` to update.
- **Rebuilt both to confirm**: `npm run build` — built `dist/index.html`
  confirmed `<title>RozNoor</title>` + the favicon link; `flutter build apk
  --release --dart-define=ROZNOOR_API_BASE_URL=https://roznoor-production.up.railway.app`
  → confirmed via `aapt dump badging` (label) and `strings` (prod URL baked
  in, `localhost:8000` absent).
- **Not confirmed this session**: the label on an actual installed device
  — no phone was connected (`adb devices -l` empty). The `aapt`-level
  confirmation above is the furthest this session could verify without one.

## Flutter release APK rebuilt against the real production backend and installed on a real device (2026-09-02, later same day) — ready for manual end-to-end testing, not yet done

With both the backend (`https://roznoor-production.up.railway.app`) and
`web_app` (`https://roznoor.up.railway.app`) now live and verified, this
session pointed the Flutter mobile app at the same real production backend
and got it running on real hardware.

- **Device confirmed real**: `flutter devices` listed `Sparx Neo 7 Ultra
  (mobile) • neo7U2401003561 • android-arm64 • Android 12 (API 31)`
  alongside the Linux-desktop/Chrome-web targets — the physical phone, not
  an emulator/simulator.
- **Config confirmed clean before building**: `lib/core/app_config.dart`'s
  `AppConfig.apiBaseUrl` is a `String.fromEnvironment('ROZNOOR_API_BASE_URL',
  defaultValue: 'http://localhost:8000')` — grepped all of `lib/` and
  confirmed it's read in exactly one place (`api_client.dart:27`, Dio's
  `baseUrl`) with zero other hardcoded `http(s)://`/`localhost`/`192.168.`
  strings anywhere else in the app.
- **Built**: `flutter build apk --release
  --dart-define=ROZNOOR_API_BASE_URL=https://roznoor-production.up.railway.app`
  → `mobile_app/build/app/outputs/flutter-apk/app-release.apk` (54.4MB).
  Confirmed for real (not assumed) that the dart-define actually won: ran
  `strings` on the built APK — the real production URL is present, and the
  `localhost:8000` default-value string is **completely absent**, i.e. Dart
  const-folded it away entirely rather than leaving it as a dead fallback.
- **Installed on the physical device**: `flutter install -d
  neo7U2401003561 --release --use-application-binary=...app-release.apk`.
  Hit one real transient blocker mid-session — the phone's `adb` connection
  dropped to "no permissions" between the initial device check and the
  install attempt (device still visible in `lsusb`, so a host/udev
  permission hiccup, not a phone disconnect) — resolved by the user
  physically unplugging/replugging the cable, confirmed via `adb devices
  -l` showing `device` state again before retrying, not just re-run and
  hoped for the best. Install then succeeded; confirmed for real via
  `adb shell dumpsys package` — `care.roznoor.roznoor_app`, `versionName
  1.0.0`, fresh `firstInstallTime`/`lastUpdateTime` both `2026-09-02
  11:56:31` — not just a clean `flutter install` exit code.
- **A real release build, not debug** — per the task's explicit
  instruction, confirmed by the `assembleRelease` Gradle task in the build
  output and the `--release` flag on both the build and install commands.

**Not done this session, by design**: no manual UI interaction with the
installed app (Voice Diary, the chest-pain hard-flag check, doctor
dashboard, etc.) — that's the user's own next step, done directly on the
device. See [[pending-device-tests]] for the exact resume note.

## Backend deployed to Railway and verified end-to-end (2026-09-02); `web_app/` deployment prep confirmed complete

The backend is now **live in production**, not just deploy-ready:
`https://roznoor-production.up.railway.app`. Postgres connected via a
`DATABASE_URL` service reference, `JWT_SECRET_KEY` set to a real generated
secret, `alembic upgrade head` ran successfully on first deploy, and
`seed.py` was run exactly once against the real production database.
**Login verified end-to-end via a real `curl` request against the deployed
URL, returning a valid JWT for a seeded patient account** — the first real
confirmation this project has of anything working against production
infrastructure, not a local/throwaway Postgres.

`web_app/`'s deployment prep (Dockerfile, nginx SPA-fallback config,
`VITE_API_BASE_URL` build-arg plumbing) — built and verified in the
2026-08-29 [[pre-deployment-checklist]] pass — was **re-confirmed correct
this session with no code changes needed**: a real `docker build` using the
actual production backend URL as the build arg (not a placeholder) showed
the URL genuinely inlined in the built bundle; a running container answered
direct `curl` hits (not client-side nav) at `/roster/2`, `/notifications`,
and `/people/new` with real `200`s serving the SPA shell, and a missing
asset still `404`s. Also confirmed (grep, not just re-reading `App.jsx`)
that the SPA route renames (`/patients` → `/roster`, `/alerts` →
`/notifications`, admin → `/people`) are consistent everywhere in
`web_app/src` — no top-level `/patients` or `/alerts` route exists
anywhere. Full narrative in [[decisions-log]].

**No backend code or Railway backend environment variables were touched
this session** — out of scope by explicit instruction.

**Still manual, on Railway's dashboard** (not part of this coding session):
create the `web_app` Railway service (Root Directory = `web_app`), set
`VITE_API_BASE_URL` to the real backend URL above as a build-arg service
variable, deploy, generate a public domain, then set `CORS_ALLOWED_ORIGINS`
on the backend service to that new domain. Exact sequence already
documented in [[pre-deployment-checklist]]'s Railway deploy runbook (Steps
2–3) — not re-derived this session, only its underlying mechanics
re-verified.

## ALL REAL-DEVICE VERIFICATION COMPLETE (2026-09-01) — every [[pending-device-tests]] item resolved; project is now fully verified end-to-end, not just feature-complete

The three real-device/real-connectivity items flagged as open at the
bottom of the 2026-08-29 entry below are now all resolved, on real
hardware, with real internet — closing out the last unverified surface
area in the entire project. Full narrative in [[decisions-log]]
(2026-09-01 entries) and per-item detail in [[pending-device-tests]].

1. **Acoustic-analysis audio upload** — 8 more independent real
   successes this session (9 total across two sessions, zero failures) —
   resolved as a side effect of the AI-key investigation below, each one
   independently confirmed via the backend log, a direct Postgres
   `SELECT` (real varying `acoustic_features`), and a filesystem
   spot-check.
2. **Flutter doctor-role real-device testing** — both seeded doctors
   verified live on the actual phone (`neo7U2401003561`): roster, patient
   detail, 5 real alert-reviews and 2 real notes (across both doctors),
   all confirmed persisted via direct Postgres `SELECT`s, plus the
   account-switch scenario re-confirmed clean on real hardware (the exact
   scenario that caught a real bug in the earlier Xvfb-only pass).
3. **Web Voice Diary real-microphone testing** — resolved, with a real
   finding along the way: a `Recognition error: network` that looked like
   a repeat of the 2026-08-29 connectivity issue turned out to be Brave
   (not Chrome) silently blocking the underlying Google speech-recognition
   service — confirmed not an app bug once the user switched to real
   Chrome, at which point the full pipeline (speech recognition →
   AI-merged symptom extraction → hard red-flag → `MediaRecorder` acoustic
   capture) worked correctly end-to-end for the first time on real
   hardware/internet.

**One unplanned but genuinely important finding surfaced along the way,
also documented in [[decisions-log]]**: mid-session, the user's own live
voice testing (spoken chest-pain phrases in English and Urdu) came back
`Green` when it should have hard-flagged `Red`. Root cause, confirmed
from the running process and the DB (not guessed): `ANTHROPIC_API_KEY`
was unset this session, so AI symptom extraction silently never ran — and
`rules.py`/`entries.py` have **no raw-transcript fallback**, meaning a
voice-only chest-pain report gets zero rule-engine protection whenever
the key is unset, not just degraded protection. Not a code bug — matches
prior sessions' documented soft-fail behavior — but worth keeping as a
real deploy/demo risk. Once the user added a real key to `.env`
themselves, re-tested and confirmed the AI-merge pipeline correctly
hard-flags chest pain in **both English and Urdu** on real hardware.

**Nothing here required an application-code change** — every fix this
session was either configuration (the API key) or diagnostic (Brave vs.
Chrome); the underlying app logic in every case was already correct.

**With this, the project has both categories of "done" it previously
lacked simultaneously**: feature-complete (2026-08-25 backend, 2026-08-29
frontends) **and** every real-device/real-connectivity gap the team
couldn't verify from a sandbox is now closed. There is no longer an open
"needs the user's own hardware" item anywhere in [[pending-device-tests]].

## PROJECT FEATURE-COMPLETE (2026-08-29, final session) — React web app admin role built and verified; all three roles now built on BOTH platforms

Built `web_app/`'s admin role (the "People & roles" screen: list, create,
edit) — the final remaining piece across the entire project. **No backend
changes** — `GET/POST /admin/users` and `PATCH /admin/users/{id}` were
already complete and verified in the 2026-08-25 doctor & admin routers
pass and the 2026-08-29 Flutter admin-role pass; re-verified with real
curl calls before any React code was written, then again through the real
browser UI. Full narrative in [[decisions-log]] and [[conventions]].

- **Built**: `PeopleScreen` (searchable table + "Invite a person"), one
  shared `UserFormScreen` for create (all four roles) and edit (name/
  role/phone_or_email/language_preference — no password field in edit
  mode, no `status` field, matching the backend's real supported fields
  exactly). `AdminDataContext` mirrors `DoctorDataContext`'s shape.
  `App.jsx` gained a third role branch (`admin` → `AdminShell`) with its
  own keyed-on-`userId` data-load guard and sign-out reset, same shape as
  the doctor branch.
- **Content/layout source**: the web prototype's `a-people` screen,
  adapted to a searchable table (a web app has the room a phone doesn't).
  Its decorative "Red-flag rule sets" card (no backing endpoint/data) was
  left out, same as the Flutter admin build.
- **Routing collision avoided proactively**: picked `/people` (not
  `/admin`) after checking `vite.config.js`'s dev-server proxy path list
  first — the exact lesson this session's own doctor-role build learned
  the hard way earlier the same day. Verified: a full-page reload/direct
  URL at `/people`, `/people/new`, and an edit URL all load the SPA
  correctly.
- **Verified for real, live, in an actual Chrome browser** (not code
  review, not mocked data, same shared backend/DB as every other pass):
  admin login + JWT-role routing, the list with real computed
  `linked_summary`/`diagnosis`, the search filter, **a user of all four
  roles created through the real form, each one's password independently
  confirmed by logging in as that new user right after** (all four also
  confirmed via a direct Postgres `SELECT`), **an existing user edited
  (renamed + language preference changed), confirmed persisted via a
  direct Postgres `SELECT`**, a non-admin (patient) login confirmed to
  never reach `/people` even via direct URL, a freshly-created non-admin
  JWT (doctor and patient) confirmed via curl to get a real `403` from
  `GET`/`POST /admin/users`, the account-switch scenario (patient → admin)
  confirmed to reload fresh data not stale state, and the doctor role
  confirmed unaffected by this session's `App.jsx` changes. Zero console
  errors throughout.
- **Test data left in the shared dev DB, not cleaned up** — same
  precedent as every prior verification pass (no `DELETE
  /admin/users/{id}` endpoint exists); flagged plainly in
  [[decisions-log]].
- **Not verified this pass**: production build/deploy behavior (same open
  item every web-app pass has flagged); a password-reset workflow
  (doesn't exist on the backend).
- Context updated: [[decisions-log]] (full narrative), [[conventions]]
  (new admin-role web section), [[api-contracts]] (new verification
  section), [[schema]] (pointer, no schema changes).

**This completes all three roles (patient/doctor/admin) on BOTH platforms
(Flutter and React web).** Combined with the backend being feature-
complete since 2026-08-25, **the entire hackathon MVP scope — backend +
both frontends + all three roles — is now built and verified.** At the
time this entry was written, three real-device/real-connectivity items
were still open — **see the "ALL REAL-DEVICE VERIFICATION COMPLETE" entry
at the top of this file: all three were resolved on 2026-09-01.**

## Flutter admin role built and verified (2026-08-29, later still) — Flutter is now feature-complete across patient/doctor/admin

Built `mobile_app/`'s admin role (the "People & roles" screen: list,
create, edit) — the smallest remaining role scope, per the task's
explicit instruction (no complex workflows). **No backend changes** —
`GET/POST /admin/users` and `PATCH /admin/users/{id}` were already
complete and verified in the 2026-08-25 doctor & admin routers pass;
re-verified with real curl calls before any Flutter code was written,
then again through the real app. Full narrative in [[decisions-log]]
and [[conventions]].

- **Built**: `PeopleScreen` (list + search + "Invite a person"), one
  shared `UserFormScreen` for create (all four roles) and edit
  (name/role/phone_or_email/language_preference — no password field in
  edit mode, no `status` field, matching the backend's real supported
  fields exactly). `AdminDataProvider` mirrors `DoctorDataProvider`'s
  shape. `root_router.dart` gained a third role branch
  (`admin` -> `PeopleScreen`); `PlaceholderScreen` is now dead code —
  every real role has its own screen.
- **Content/layout source**: the web prototype's `a-people` screen,
  adapted to mobile stacked cards. Its decorative "Red-flag rule sets"
  card (no backing endpoint/data) was left out rather than faked.
- **Verified for real, live, end-to-end** (Xvfb `:99` + the same
  already-running real backend/Postgres every other pass this project
  has used): real admin login (Sadia Kamran) routed by JWT role to the
  new screen; the list showing all real users with correct computed
  `linked_summary`/`diagnosis`; the search filter; **a user of all four
  roles (patient/doctor/attendant/admin) created through the real form,
  each one's password independently confirmed by logging in as that new
  user right after** (same pattern the backend's original 2026-08-25
  verification used), all four also confirmed via a direct Postgres
  `SELECT`; **an existing user edited (renamed + language preference
  changed) through the real form, confirmed persisted via a direct
  Postgres `SELECT`**; a non-admin (patient) login confirmed to never
  reach the People screen at all (routed to the ordinary `PatientShell`
  instead); a freshly-created non-admin JWT (doctor and patient)
  independently confirmed via curl to get a real `403` from
  `GET`/`POST /admin/users`, rendered through the same graceful
  `ApiException`-driven error path every other role's screens already
  use. `flutter analyze` clean (only the same pre-existing style-level
  `info` lints).
- **Test data left in the shared dev DB, not cleaned up** — no
  `DELETE /admin/users/{id}` endpoint exists; flagged plainly in
  [[decisions-log]], following the same precedent every prior
  verification pass in this project has set.
- **Not verified this pass**: anything on a real Android/iOS device
  (Linux-desktop-under-Xvfb only, same limitation as every other
  Flutter pass); a password-reset workflow (doesn't exist on the
  backend).
- Context updated: [[decisions-log]] (full narrative), [[conventions]]
  (new admin-role Flutter section), [[api-contracts]] (new verification
  section), [[schema]] (pointer, no schema changes).

**This completes all three roles (patient/doctor/admin) on Flutter** —
the mobile app now has zero placeholder screens left for any real
backend role. The React web app's admin role is still unbuilt (out of
this session's scope) — see "Not yet started" below.

## React web app doctor role built and verified (2026-08-29, later same day) — doctor role now complete on BOTH platforms

Built `web_app/`'s doctor role (roster, patient detail, alerts panel),
mirroring `mobile_app/lib/`'s already-verified doctor section (see the
Flutter doctor-role entry below) and the same `d-patients`/`d-detail`/
`d-alerts` prototype screens that build used. **No backend changes** —
every doctor endpoint re-verified with real curl calls before any React
code was written, then again through the real browser UI. Full narrative
in [[decisions-log]] and [[conventions]].

- **Two real bugs found and fixed this session** (not present in the
  Flutter build, web-specific): (1) the doctor SPA routes initially
  collided with `vite.config.js`'s dev-server backend proxy path prefixes
  (`/patients`, `/alerts`) — a full page load/refresh at those URLs hit
  the backend directly instead of the app; renamed to `/roster`/
  `/notifications`. (2) `PatientOut` has no field for the patient's own
  name, so the detail header initially showed "Patient #2" instead of
  "Zubaida Bibi" — fixed by looking the name up from the already-loaded
  roster/alerts data instead. See [[decisions-log]] for both.
- **The exact account-switch scenario the task asked to re-check, verified
  clean**: switching from Dr. Ayesha Farooq to Dr. Hamza Iqbal (logout,
  log back in as the other doctor) showed correctly scoped data each
  time, no stale carryover — the keyed-on-`userId` data-load guard this
  build used from the start (informed by the real bug the Flutter build
  found and fixed in `root_router.dart`) held up under direct testing.
- **Verified for real, live, in an actual Chrome browser** (not code
  review, not mocked data, same shared backend/DB as every other pass):
  doctor login + JWT-role routing, roster with real risk-colored rows and
  correct "N monitored · N need attention" counts, patient detail with
  real weight/sleep trend lines (raw values, same known baseline-band
  backend-scope gap as Flutter) + check-in history + alert history + doctor
  notes, adding a note (confirmed persisted via direct Postgres `SELECT`,
  not just UI state), marking an alert reviewed (confirmed persisted via
  direct Postgres `SELECT`, live badge-count update), the Unread/All
  filter, the roster search filter, cross-doctor RBAC (a 403 rendered
  gracefully, not someone else's data), zero console errors throughout.
- **Not verified this pass**: production build/deploy behavior (same
  open item every web-app pass has flagged); the admin role — explicitly
  out of scope, next future session.
- Context updated: [[decisions-log]] (full narrative + both bugs),
  [[conventions]] (new doctor-role web section), [[api-contracts]] (new
  verification section), [[schema]] (pointer, no schema changes).

**This completes the doctor role on both platforms** (Flutter + React
web). Admin role is unbuilt on either platform — explicitly deferred to a
separate future session, per this session's task scope.

## React web app built and verified (2026-08-29, later same day) — patient role, real microphone still pending

Built `web_app/` (Vite + React, JavaScript) — patient/attendant role only,
mirroring `mobile_app/` (Flutter) against the exact same unmodified
backend. Doctor/admin web screens are explicitly next-session scope (same
placeholder pattern `mobile_app` used before its own doctor role existed).
Full design rationale, file-by-file mapping, and verification narrative in
[[decisions-log]] and [[conventions]].

- **No backend changes at all.** Every endpoint reused verbatim from
  [[api-contracts]]; re-verified live through the real browser UI (see
  below), not just trusted from the doc.
- **Both design sources read, as the task asked**: the prototype
  (`RozNoor.dc.html`'s patient screens) for visual/content, AND
  `mobile_app/lib/` for exactly which API calls/data shapes/edge cases
  were already solved — so the language-toggle exclusivity fix, the
  sequenced audio-capture design, the JWT/session handling shape, and the
  client-computed Weekly Digest were all reused/ported rather than
  re-solved from scratch.
- **CORS handled via a Vite dev-server proxy**, not backend CORS
  middleware (backend change, out of scope) — see [[decisions-log]] for
  the production-deployment caveat this leaves open.
- **JWT storage: `localStorage`**, flagged plainly (not an httpOnly
  cookie — unavailable without a backend change) — see [[decisions-log]]
  for the full trade-off writeup.
- **Voice capture: Web Speech API + MediaRecorder**, NOT
  speech_to_text/record. Real, flagged behavioral differences (browser
  support, cloud- vs. on-device recognition, HTTPS-in-production
  requirement) — see [[conventions]]. **The acoustic-analysis audio-upload
  question the task flagged as possibly infeasible on web turned out
  feasible and was built, not skipped** — the backend already accepts
  `webm` (MediaRecorder's default Chrome output), decoded via the same
  `ffmpeg` path as every other format.
- **Verified for real, live, in an actual Chrome browser** (not code
  review, not mocked data): login (success + wrong-password + doctor
  role-routing), a hard-Red-flag Quick Check-in (Chest pain) end-to-end
  through the real rule engine, a typed-fallback Voice Diary entry, real
  Timeline data (including entries seeded by prior Flutter real-device
  passes — same shared DB), Weekly Trends, Profile with real fields and a
  correctly-advancing `day_count`, the emergency-contact modal, logout.
  Paper/Nocturne theme confirmed instant, complete, and persisted across a
  reload. Language toggle confirmed exclusive AND confirmed to correctly
  reset to the account's stored preference on a fresh load (non-persistent
  by design). Zero console errors throughout.
- [ ] **Real browser-microphone recording** (`SpeechRecognition` +
  `MediaRecorder` against actual audio input) — NOT verified this
  session, no audio input hardware in the sandboxed browser environment
  used. Same substitution (typed-fallback path instead) every `mobile_app`
  sandbox pass made before real-device testing existed. See
  [[pending-device-tests]] for the exact resume condition — a real
  browser/OS with a microphone, not a phone.
- Context updated: [[schema]], [[conventions]], [[api-contracts]],
  [[decisions-log]], [[pending-device-tests]].

## Flutter doctor role built and verified (2026-08-29) — real-device pass still pending WiFi

**Explicit user override of the standing Phase-2 hold** — see
[[pending-device-tests]] and [[decisions-log]] for the full conflict and
why it was surfaced rather than silently resolved either way. The
acoustic-audio item below this section was NOT touched this session.

Built: doctor home/patient roster (`GET /doctors/{id}/patients`), patient
detail (full check-in timeline via the same `GET /entries/{patient_id}/
timeline` the patient app calls, plus raw-value weight/sleep trend charts,
alert history, and doctor notes view+add), an alerts panel (`GET
/doctors/{id}/alerts` + `POST /alerts/{id}/review`), and JWT-role routing
into all of it (`root_router.dart` now sends `role == 'doctor'` to the new
`DoctorShell` instead of the placeholder; admin still lands on the
placeholder — out of this session's scope). Content/layout source: the web
prototype's `d-patients`/`d-detail`/`d-alerts` screens, per the plan
already recorded in [[conventions]] from an earlier session (confirmed
still present, as this session's task asked) — adapted to mobile stacked
cards + a bottom sheet for adding a note. Full file-by-file breakdown in
[[conventions]]; full design/verification narrative in [[decisions-log]].

**No backend changes** — every endpoint needed was already complete per
the task brief; re-verified all of them with real curl calls before
writing any Flutter code against them (see [[decisions-log]]).

**One real backend-scope gap found and flagged, not silently worked
around**: no endpoint exposes `baseline_history`'s min/max bands, so the
patient-detail trend charts show actual recorded values over time rather
than the prototype's shaded "learned normal" band — see [[decisions-log]]
and [[conventions]].

**One real pre-existing bug found and fixed**: `root_router.dart`'s
once-per-sign-in data-load guard actually only ever fired once per app
launch (not per sign-in), and `PatientDataProvider.reset()` was dead code.
Fixed so logging out and back in (same or different account) reliably
reloads — verified live by switching between the two seeded doctor
accounts and confirming no stale roster data crossed over. See
[[decisions-log]].

**Verified for real, live, end-to-end** (Xvfb `:99` + real backend + real
Postgres, driven via a new scratchpad `python-xlib` helper — no phone
involved): both seeded doctors log in and see only their own patients;
roster/detail/alerts render real data with correct risk colors and
counts; adding a doctor note through the UI persisted (confirmed via a
follow-up fetch); marking an alert reviewed persisted (confirmed via a
direct Postgres `SELECT`, not just UI state) and updated the unread badge
live; `flutter analyze` clean (no new errors/warnings). Full checklist in
[[decisions-log]].

- [ ] **Doctor role real-device testing** — NOT done this session (Linux-
  desktop-under-Xvfb only, no phone available). Pending the same "phone
  back on the dev machine's WiFi" condition as the acoustic-audio item
  below — see [[pending-device-tests]], which now tracks this as a second,
  independent pending item (does not block on the acoustic-audio item and
  isn't blocked by it either; they're unrelated code paths).

**Incidental finding, pre-existing, not caused by this session**: `flutter
test` (the one committed test, `test/widget_test.dart`) currently fails.
Confirmed via `git stash` that it fails identically on the unmodified
codebase before any of this session's changes — not a regression from the
doctor-role work. Not investigated further (out of this session's stated
scope), but flagging since the suite is currently red on `main` and no
prior session's progress notes mention it.

## Real-device verification pass, IN PROGRESS (2026-08-28) — paused for travel (no WiFi), resume via [[pending-device-tests]]
**Start here, not the 2026-08-27 section below** — that section is now
superseded by this one for the acoustic-upload item specifically (kept
below only for the earlier label-bug/mic-contention history, which is
still accurate). Full investigation trail in [[decisions-log]] (2026-08-28
entry, plus the 2026-08-27 entry above it). **Exact resume steps —
what needs to be running, what to ask the user to do, and the two other
still-open device-checklist items — are in [[pending-device-tests]].**
Read that file first when picking this back up; don't re-derive it.

- [x] **Acoustic-analysis audio upload — root cause FOUND (two real bugs,
  both fixed) and confirmed working ONCE, end-to-end, for real** (entry
  43: backend logged `POST /entries/43/audio 200 OK`, DB confirmed
  `audio_file_path` + `acoustic_features`, file confirmed on disk at
  100,261 bytes). **NOT yet called fully resolved** — per this task's own
  explicit "don't declare fixed on one success" instruction, since the
  earlier failures looked intermittent. Needs 2 more clean confirmations,
  each independently checked in the DB, before this checklist item can be
  marked genuinely done. See [[pending-device-tests]] for the exact resume
  procedure — session paused mid-way through gathering those confirmations
  because the user is traveling with no WiFi (phone can't reach the LAN
  backend right now — an environment limitation, not a new failure).

## Real-device verification pass, PARTIALLY SUPERSEDED (2026-08-27) — cut short by low battery
Full investigation trail in [[decisions-log]] (same date, "Voice Diary
investigation" entry) — this is the checklist-level status only. **The
acoustic-analysis upload line below is stale — see the 2026-08-28 section
above for what actually happened next.** The rest of this section (theme
toggle, language toggle, speech-to-text, quick check-in) is still accurate
and not yet re-touched.
- [x] **App icon** — device-verified: real pulse icon on home screen, not
  the default Flutter logo.
- [ ] **Paper/Nocturne theme toggle** — not yet device-tested this pass
  (verification got diverted into the Voice Diary investigation below
  before reaching this item).
- [x] **Language toggle exclusivity** — device-verified: login and other
  screens show one language at a time. A separate, cosmetic label bug on
  Voice Diary's own toggle (showed the switch-target language, not the
  active one) was found and fixed — see [[decisions-log]].
- [ ] **Voice Diary end-to-end** — PARTIALLY device-verified, real bugs
  found and only partially fixed:
  - [x] Speech-to-text transcription — device-verified working, after
    fixing a real mic-contention bug (concurrent `AudioRecorder` +
    `SpeechRecognizer` starved the recognizer of audio entirely on this
    device). Fix: sequenced capture, speech first then a 6s follow-up
    recording. See [[decisions-log]] for the full root-cause trail.
  - [ ] ~~Acoustic-analysis audio upload — device-verified STILL BROKEN...~~
    **STALE, see the 2026-08-28 section above** — root cause found (two
    real bugs) and fixed, one clean end-to-end success confirmed, 2 more
    confirmations still needed before this line can be checked off.
  - [ ] Submission returning a sensible risk result — not separately
    re-checked this pass (the transcript-only path was already verified in
    earlier passes); should still hold since nothing in this pass touched
    the risk-evaluation call path, but wasn't re-confirmed live.
- [ ] **Quick check-in regression check** — not yet re-tested this pass.

## Three Flutter patient-app UI/UX fixes (2026-08-27) — theme, language exclusivity, launcher icon — all verified for real
Unrelated to the acoustic-signal pass below; patient-role Flutter app only.
Full design rationale, threshold/color sourcing, and the complete
verification narrative are in [[decisions-log]] (2026-08-27 entry) — this
is the short version.
- **Paper/Nocturne theme toggle**: `lib/state/theme_provider.dart` (new
  `ThemeProvider`, `ThemeMode` + `shared_preferences` persistence — new
  dependency), `RnDarkColors` + `buildRnDarkTheme()` added to `lib/core/
  theme.dart` (real Nocturne values ported from the prototype, not
  invented), wired into `MaterialApp` (`darkTheme`/`themeMode`) in
  `main.dart`, toggle UI added to Profile (`SegmentedButton`, "Paper"/
  "Nocturne", next to the existing Roman Urdu switch). Also fixed a real
  pre-existing bug found while wiring this: ~20 call sites across 9
  screens hardcoded `Colors.black.withValues(alpha: ...)` for secondary
  text, invisible against Nocturne's dark backgrounds — replaced with a
  new theme-aware `context.rnMuted()` extension.
- **Language toggle exclusivity**: audited every patient screen + login
  line-by-line. Only `login_screen.dart` had the bug (two always-visible
  Text widgets, Roman Urdu then English, never gated on the toggle) — 
  fixed by switching to `BilingualText` like every other screen already
  correctly did. Everything else was already exclusive.
- **App icon**: generated programmatically via a new committed script
  (`mobile_app/scripts/gen_app_icon.py`, Python + Pillow) — a stylized
  teal heartbeat/pulse glyph, in the app's real brand colors. Two
  concepts (pulse, leaf) were shown to the user first; pulse was picked.
  Applied via `flutter_launcher_icons` (new dev dependency) to both
  Android (adaptive icon: teal background layer + inset glyph
  foreground) and iOS (`remove_alpha_ios: true`).
- **Verified for real, live** (not just code-reading or `flutter
  analyze`): built `flutter build linux --debug`, ran on an isolated
  Xvfb display (deliberately not the sandbox's real `:1`, which turned
  out to be the user's own live desktop — caught and corrected
  immediately, see [[decisions-log]]), drove it via synthetic X11 events,
  logged in against a real seeded backend as Zubaida Bibi
  (`roman_urdu` preference). Confirmed: Login shows exactly one language
  line; the theme toggle instantly re-themes the whole app including
  previously-invisible secondary text in Nocturne; Nocturne AND the
  logged-in session both survive a full process kill + relaunch (real
  persistence, not just in-memory state); Home/Quick Check-in/Login all
  legible in Nocturne; the actual generated
  `android/.../mipmap-xxxhdpi/ic_launcher.png` file renders the pulse
  icon correctly.
- **Not verified**: the launcher icon on an actual Android/iOS
  device/emulator (no SDK license accepted / no emulator in this
  sandbox); Nocturne `FilterChip`/`SegmentedButton` selected-state colors
  weren't pixel-matched to the dark palette (legible, not un-audited for
  on-brand accuracy — a couple of call sites still hardcode light-only
  `RnColors.accent200`/`accentDark`).
- A build-environment blocker unrelated to this session's own changes had
  to be fixed to get any Linux build working at all: pinned
  `record_platform_interface: 1.2.0` via `dependency_overrides` (a
  from-scratch `pub get` otherwise resolves a version `record_linux
  0.7.2` — added in the prior acoustic-analysis pass — can't actually
  compile against). See [[decisions-log]] for the full story, including
  the `libsecret-1-dev` workaround needed in this particular sandbox.
- Context updated: [[decisions-log]] (full rationale + verification
  narrative), [[conventions]] (new theme-provider/dark-mode-text
  conventions + updated Flutter folder structure).

## Acoustic-signal analysis for Voice Diary (2026-08-25) — backend verified for real, mobile capture needs a real device
Deterministic signal-processing feature extraction (numpy + system `ffmpeg` — NOT a
machine-learning model, no training data exists) for Voice Diary recordings, feeding
the existing rule engine as an additional Layer-B-only signal. See [[decisions-log]]
for the full design rationale (why `POST /entries/{id}/audio` is a separate endpoint,
threshold proposals needing review, the concurrent-mic-access risk, the mid-build
pivot away from librosa, the baseline-snapshot simplifying assumption). Timeline risk
was flagged to the user up front per their explicit request, before implementing.
- **Backend**: `entries.audio_file_path` + `ai_results.acoustic_features` columns
  (migration `4674989821f7`), `app/services/audio_analysis.py` (pause ratio/
  speaking-rate proxy, energy/amplitude variance, pitch variability, a derived
  `possible_fatigue_or_breathlessness` flag), `rules.py` extended with an optional
  acoustic score contribution (Layer-B only, never a hard flag), new
  `POST /entries/{id}/audio` endpoint, `ai.py`'s summary prompt extended to cite
  acoustic features when present. Local-disk storage (hackathon-scope shortcut, see
  [[decisions-log]]).
- **Mobile**: `record` + `path_provider` packages, `AudioRecorderService` capturing
  alongside `speech_to_text`, `EntryService.uploadAudio()`,
  `PatientDataProvider.attachAudio()`, Voice Diary screen wired to record/stop/upload
  best-effort after a successful entry submission. Also fixed a pre-existing gap:
  iOS `Info.plist` was missing microphone/speech-recognition usage descriptions
  entirely (never added during the original speech_to_text pass) — added both.
- **Verified for real** against a fresh throwaway Postgres + running FastAPI instance:
  real signal-processing feature extraction on synthetic "calm" vs. "exaggerated
  pauses/flat energy" WAV files (caught and fixed a real bug in the process — see
  [[decisions-log]]); m4a/AAC decoding (the mobile recorder's actual format) via
  `ffmpeg`; the full `POST /entries` -> `POST /entries/{id}/audio` HTTP flow; a
  genuinely corrupt upload soft-failing correctly (file saved, `risk_result`
  untouched); the acoustic signal **measurably flipping a real `risk_level` Green ->
  Yellow** when combined with a manually-ticked symptom, with a correct `alerts` row
  created and surfaced through the real `GET /doctors/{id}/alerts` endpoint as the
  patient's actual assigned doctor — confirms "visible to doctors" end-to-end, not
  just at the schema level; existing quick-entry and transcript-only voice-entry paths
  confirmed byte-for-byte unaffected; `POST /patients/{id}/ai-summary` still
  soft-fails cleanly with no API key configured. Full narrative in [[decisions-log]].
- **Not verified this pass** (flagging, not silently skipping): live concurrent
  microphone capture (`speech_to_text` + `record` running at once) on an actual
  Android/iOS device — no microphone hardware in this sandbox, same limitation as
  every prior mobile pass, needs the user's own real-device test; the hand-rolled
  autocorrelation pitch tracker's accuracy against real (non-synthetic) human speech.
- Context updated: [[schema]] (2 new columns, 1 migration), [[decisions-log]] (full
  design rationale + threshold proposals + verification narrative + the librosa
  pivot), [[conventions]] (new `audio_analysis.py` section + mobile
  concurrent-mic-access note), [[api-contracts]] (new `POST /entries/{id}/audio`
  endpoint + `EntryOut` additions).

## Flutter patient app is built and verified for real (2026-08-25)
The Flutter mobile app (`mobile_app/`) now exists — patient/attendant role only,
per this session's scope; doctor/admin screens are still a placeholder pending a
later phase. Backend is otherwise unchanged in scope from the note below, plus
three small additive endpoints/fields this pass required (see below).

## Backend is feature-complete for the hackathon MVP scope (2026-08-25)
Every backend item across all task passes is built and verified for real. What's
left before a demo is frontend work (React admin/doctor web app + Flutter doctor/
admin screens) — no more backend routers/services are planned in this scope
beyond the three small additive pieces the Flutter patient-app pass needed (see
below). See "Not yet started" below for what's explicitly out of scope (weekly
digest generation, refresh tokens) rather than merely deferred.

## Done — Flutter patient app (2026-08-25)
- **New Flutter project** (`mobile_app/`, `flutter create`), patient/attendant
  role only per this session's scope — see [[conventions]] for the full folder
  structure, state-management/API-client/secure-storage conventions.
- **Role-switcher tabs**: confirmed not present in any existing shippable code
  (no Flutter or React app existed in the repo before this session) — only in
  the design prototype, where they're an expected preview tool. The Flutter
  app was built with no such control from the start: `root_router.dart`
  decides post-login routing purely from the JWT's `role`. See
  [[decisions-log]].
- **Login**: one screen/form (`login_screen.dart`) calling the existing
  `POST /auth/login`, with a secondary "Are you a doctor or admin? Log in
  here" link to the same form with `isClinician: true` (copy/color only —
  same endpoint, same routing logic). Post-login routing reads `session.role`
  only; doctor/admin land on a placeholder screen (later phase).
- **Real API wiring, no mock/local JSON**: Home, Voice Diary, Quick Check-in,
  Result, Timeline, Profile all call the live backend
  (`AuthService`/`PatientService`/`EntryService`). Weekly Digest ("Trends")
  has no dedicated backend endpoint yet, so it's computed client-side from
  real `GET /entries/{id}/timeline` data instead — see [[decisions-log]].
- **JWT storage**: `flutter_secure_storage`, attached to every request via a
  single `Dio` interceptor (`lib/core/api_client.dart`).
- **Voice Diary**: `POST /entries` with `entry_type=voice` + `raw_transcript`,
  using the `speech_to_text` package (on-device STT) with a typed-text
  fallback matching the prototype's own documented behavior. The language
  toggle sets the STT locale (`en-US`/`ur-PK`), so it affects voice
  processing input, not just static text.
- **Quick Check-in**: `POST /entries` with `entry_type=quick` + 1-5 sliders
  (energy/mood/appetite/mobility), an hours field for sleep (a deliberate
  deviation from the prototype's mockup — see [[decisions-log]]), an optional
  weight field, `medicine_status`, and a symptom checklist loaded from a new
  `GET /patients/{id}/symptom-checklist` endpoint.
- **Result screen**: displays the real `risk_results` from that submission
  (risk_level, risk_title, risk_message, reasoning) plus `symptom_names`
  chips; omits the prototype's separate numeric baseline-deltas card since
  `ai_results.deviation_deltas` has no exposing endpoint.
- **Timeline**: `GET /entries/{patient_id}/timeline`, newest-first.
- **Profile**: real patient data (`GET /patients/{id}` + `GET /auth/me`),
  view-only — no `PATCH` endpoint exists yet for any patient-editable field.
- **Three small additive backend changes** (no schema/migration changes —
  see [[schema]]): `patient_id` added to `GET /auth/me`'s response;
  `PatientOut` extended with `emergency_contact_name`/
  `emergency_contact_phone`/`medication_info`/`attendant_name`/
  `assigned_doctor_name`; new `GET /patients/{id}/symptom-checklist`. All
  three flagged in detail in [[decisions-log]] since the task framed this
  session as Flutter-only.
- **Verified end-to-end against the real backend** (fresh throwaway Postgres +
  running FastAPI, no `ANTHROPIC_API_KEY` configured) — built with `flutter
  build linux --debug` and driven with real synthetic input on an isolated
  `Xvfb` virtual display (screenshotted at every step): real patient login,
  a hard-Red-flag quick check-in (Chest pain) producing the correct rule-
  engine result end-to-end, a typed-fallback voice entry producing a correct
  Green result, the timeline reflecting every entry submitted, Profile
  showing real linked data, the language toggle changing real UI text, and a
  real doctor account correctly routed to the placeholder screen via the
  clinician login link. Full narrative, including an environment mistake
  made and corrected mid-session and a real bug found and fixed (logout
  from a pushed screen not returning to the login screen), is in
  [[decisions-log]]. **Not verified this session**: live microphone speech
  recognition (no audio hardware/emulator in this sandbox), the AI-merged
  voice path (`source: "merged"` — no API key configured; already verified
  with a real key in the earlier AI-layer pass), and anything on an actual
  Android/iOS device or emulator.
- Context updated: [[schema]] (no DB changes, pointer only), [[decisions-log]]
  (full design rationale + verification narrative), [[conventions]] (new
  Flutter-side conventions section + doctor/admin design-source note for the
  next phase), [[api-contracts]] (3 endpoint/field additions).

## Done — Doctor & admin routers (2026-08-25)
- **Doctor routers** (`app/routers/doctors.py`, two `APIRouter`s since the paths
  don't share one prefix):
  - `GET /doctors/{doctor_id}/patients` — roster (name, MR number, age, diagnosis,
    day_count/baseline_stage, latest risk_level + reasoning, last entry timestamp),
    sorted most-recently-active first. RBAC: doctor (self) or admin
    (`get_authorized_doctor`, new dependency in `app/core/deps.py`, same
    shape/pattern as `get_authorized_patient`).
  - `GET /doctors/{doctor_id}/alerts` — alerts across the doctor's own patients
    only, optional `?reviewed=true|false` filter, newest first. Same RBAC.
  - `POST /alerts/{alert_id}/review` — marks `alerts.reviewed=true`. RBAC:
    `require_roles(doctor, admin)` + a new `is_authorized_clinician_for_patient`
    check (doctor must be the alert's patient's assigned doctor; admin always).
- **Doctor notes** (`app/routers/patients.py`, same `/patients` prefix as the
  existing patient routes): `POST`/`GET /patients/{patient_id}/notes`.
  Doctor/admin ONLY — deliberately narrower than every other patient-scoped route
  in this app (no patient/attendant self-access) via a new `get_clinician_patient`
  dependency. See [[decisions-log]] for why.
- **Admin routers** (`app/routers/admin.py`, admin-only throughout via the
  existing `require_roles`):
  - `GET /admin/users` — every user, with a computed `linked_summary` (doctor's
    patient count / patient's assigned doctor / attendant's linked patient /
    "System" for admin) and `diagnosis` for patients — matches the "People &
    roles" screen in the UI prototype.
  - `POST /admin/users` — create any-role user, reuses `hash_password` (no new
    hashing logic), 409 on a duplicate `phone_or_email`.
  - `PATCH /admin/users/{user_id}` — partial edit of name/role/phone_or_email/
    language_preference. **No `status` field** — `users` has no such column and
    none was added; see [[decisions-log]] and [[schema]].
- **No schema/migration changes** this pass — every table/column already existed.
- **Verified end-to-end** against a fresh throwaway Postgres + running FastAPI
  instance, real HTTP requests, full RBAC matrix (48 checks, all passed on first
  run): correct role succeeds; wrong doctor 403s on another doctor's roster/
  alerts/note-write; admin always succeeds; patient/attendant blocked entirely
  from doctor- and admin-only routes (including the ones where they'd normally
  have read access via `get_authorized_patient`, since notes are clinician-only);
  404s on nonexistent doctor/alert/user ids; 409 on duplicate email at both
  create and update; 422 on an empty PATCH body; unauthenticated -> 401; a newly
  admin-created user's password actually works for login (real bcrypt hash, not
  a placeholder). Also separately confirmed the AI layer's previously-untested
  "no checklist defined for this diagnosis" skip path (flagged in the prior
  pass): a voice entry for a COPD-diagnosis patient (maps to the generic
  ruleset, no `CHECKLIST_DIAGNOSIS_SEARCH_TERMS` entry) correctly never called
  `ai_service.extract_symptoms()` at all, stayed `source='rule'`, wrote no
  `ai_results` row.
- Context updated: [[schema]] (two "as of" notes, no migration), [[decisions-log]]
  (RBAC design + doctor_notes/status scoping decisions), [[conventions]] (new
  routers/deps section), [[api-contracts]] (6 new endpoints).

## Done — AI layer (2026-08-25)
- `app/services/ai.py` — Claude API integration (`claude-opus-5`), fully soft-fail
  (returns `None` on any error, never raises):
  - `extract_symptoms()` — voice-entry transcripts (Roman Urdu / mixed / English) ->
    structured symptom extraction via `client.messages.parse(output_format=...)`.
    Matches against the patient's actual diagnosis checklist only.
  - `generate_patient_summary()` — plain-language paragraph over recent entries +
    baseline bands, for the Result screen / doctor "Generate AI Summary" button.
  - `compute_deviation_deltas()` — plain-Python (not AI) per-metric baseline
    comparison for `ai_results.deviation_deltas`.
- **Merge logic** (`app/routers/entries.py`): for a voice entry, AI-detected symptoms
  are folded into the SAME symptom set the rule engine scores — including hard
  red-flags. The rule engine always runs regardless; AI only ever supplies additional
  symptom evidence into it, never assigns risk on its own.
  `risk_results.source` = `'merged'` when AI actually ran this call, else `'rule'`
  (this implementation never produces `'ai'` alone — see [[decisions-log]] for why).
- `POST /patients/{patient_id}/ai-summary` — the "Generate AI Summary" endpoint,
  same RBAC as `GET /patients/{patient_id}`. Returns
  `{available, summary_text, fallback_message}`, never a 500.
- `ANTHROPIC_API_KEY` added to `Settings` (`app/core/config.py`), env-var only,
  defaults to `None` (a valid, expected state — AI-unavailable is a first-class path,
  not an error case).
- **No schema/migration changes** — `ai_results` already had exactly the columns
  needed.
- **Verified end-to-end with a REAL Anthropic API key** (provided by the user for this
  test, written only to a gitignored local `.env`, removed again afterward — never
  logged/committed): both fallback paths (no key, invalid key -> real 401) confirmed
  graceful with no crash and correct logging; real Roman Urdu transcripts correctly
  extracted symptoms with no manual ticks, including the critical safety case — a
  chest-pain transcript alone (no checkbox) correctly triggered the hard Red flag
  through the merged rule engine; a benign transcript produced zero false-positive
  matches; the AI summary endpoint produced a real, accurately-grounded, correctly
  self-disclaiming paragraph. One path not separately exercised: the
  no-checklist-for-this-diagnosis skip (low-risk, simple guard) — noted in
  [[api-contracts]].
- Context updated: [[schema]], [[decisions-log]] (full design rationale + verification
  detail), [[conventions]] (new AI-layer section), [[api-contracts]] (new endpoint +
  updated `POST /entries` contract).

## Done — Weight tracking (2026-08-24)
- Added `entries.weight_value` (nullable numeric, kg) — a real schema change,
  explicitly confirmed by the user first. Migration:
  `3973a8111b8e_add_entries_weight_value.py`, autogenerated cleanly (one-column diff).
- Wired into `app/services/rules.py` as `HEART_FAILURE_RULES["hard_red_weight_gain"]`
  (doc-sourced: >=2.0kg within 3 days, checked against the lowest reading in that
  window) and into `app/services/baseline.py`'s tracked metrics (its own
  `baseline_history` band, for charting — kept out of the generic below-band
  deviation scorer since weight's danger direction is a rise, not a dip; see
  [[decisions-log]]/[[conventions]]).
- `seed.py` updated: Zubaida Bibi's entries now carry a real weight trajectory
  (62.0kg -> 64.4kg) matching the "+2.4 kg / 5 days" text already in her seeded
  alert/reasoning; Ghulam Rasool and Mukhtar Ali got stable weight trends as a
  no-false-positive contrast case.
- **Verified end-to-end** via real `POST /entries` calls: a clear jump -> Red; the
  exact 2.0kg/3-day boundary -> Red, 1.9kg -> not Red; a gradual gain spread past the
  3-day window -> not flagged; a stable patient's normal weight change -> Green;
  baseline_history/weight updates correctly; a weight-only quick entry is valid.
- Context updated: [[schema]], [[decisions-log]], [[conventions]], [[api-contracts]].

## Done — Rule-based safety engine (2026-08-24)
- `POST /entries` — check-in submission (voice or quick), role-gated to
  patient/attendant, patient-ownership enforced via a body-param RBAC check
  (`is_authorized_for_patient`, extracted from `get_authorized_patient` — see
  [[decisions-log]]). Stores into `entries` + `entry_symptoms`.
- `app/services/baseline.py` — three-stage baseline tracking (cold_start/learning/
  personalized), pure Python, recomputes `baseline_history` + `patient.day_count`/
  `baseline_stage` from real entry history on every submission. Formula proposed by
  Claude Code (doc names the stages, not the math) — flagged for review in
  [[decisions-log]].
- `app/services/rules.py` — disease-specific red-flag + weighted scoring engine,
  keyed off `patients.diagnosis` (heart_failure / post_surgical / generic fallback).
  Hard red-flags bypass baseline entirely (e.g. chest pain -> instant Red); otherwise
  a composite score from symptom weights + baseline deviation + below-band streaks +
  missed-dose adherence maps to Green/Yellow/Orange. Every threshold is either cited
  back to the project doc/UI prototype or explicitly flagged "NEEDS REVIEW" — see
  [[decisions-log]] for the full sourcing breakdown.
- Produces a `risk_results` row per entry (`source='rule'` always, per task scope — no
  AI called anywhere in this pass) plus an `alerts` row for any non-Green result.
- `GET /entries/{patient_id}/timeline` — entries + nested risk_result, newest first,
  same RBAC as `GET /patients/{patient_id}`.
- **Verified end-to-end** against a fresh throwaway Postgres + running FastAPI
  instance (no new migration needed — every column already existed): chest-pain hard
  flag -> Red, plain entry -> Green, combined deviation+streak+adherence -> Yellow
  with correct compound reasoning, full RBAC matrix across
  patient/attendant/doctor/other-patient, Pydantic 422s on bad input, alerts created
  only for non-Green, timeline ordering and RBAC. Also observed and documented a real
  interaction: a seeded patient's fictional `personalized`/high-day-count status gets
  recomputed down to what their *actual* entry history supports the moment they get
  one real submission (expected behavior, not a bug — see [[decisions-log]]).
- Context updated: [[schema]] (weight gap, baseline_history now live), [[decisions-log]]
  (full threshold-sourcing breakdown), [[conventions]] (services/ conventions),
  [[api-contracts]] (both new endpoints).

## Done — Authentication (2026-08-24)
- Password hashing: `app/core/security.py` — bcrypt via the `bcrypt` package directly
  (`hash_password`/`verify_password`). `seed.py` updated to hash a real shared demo
  password (`RozNoor@123`) for every seeded user, replacing the old placeholder string.
- Login: `POST /auth/login` — JSON body `{phone_or_email, password}`, returns a JWT
  (`TokenResponse`) encoding `sub=user_id` and `role`. 24h expiry, no refresh token
  (out of scope for this MVP — see [[decisions-log]]).
- `GET /auth/me` — returns the caller's own identity from the token; useful both as a
  real endpoint and as a quick way to validate a token.
- Reusable auth dependency: `app.core.deps.get_current_user` — every protected route
  depends on this rather than re-parsing tokens itself.
- RBAC: `app.core.deps.require_roles(*roles)` (role-gate factory) and
  `app.core.deps.get_authorized_patient` (patient-ownership gate — admin always,
  doctor if assigned, patient if self, attendant if linked). Proven via a minimal
  `GET /patients/{patient_id}` endpoint (`app/routers/patients.py`).
- **Verified end-to-end** against a throwaway local Postgres + running FastAPI
  instance: login success/failure, `/auth/me` with/without token, and the full RBAC
  matrix (patient self/cross-access, doctor own/other-doctor's patient, admin
  any-patient, 404 on missing patient, 401 on garbage token) — all matched spec.
  Confirmed `password_hash` in the DB is a real `$2b$...` bcrypt hash, not the old
  placeholder. Container torn down afterward.
- `docs/RozNoor_Mobile_UI_Field_Requirements.docx` read in full (now present). Locked
  the 1-5 quick-check-in scale decision per the user's explicit confirmation — updated
  in [[decisions-log]] and [[schema]].
- Context updated: [[schema]], [[decisions-log]], [[conventions]], and new
  [[api-contracts]] (endpoint-by-endpoint request/response reference).

## Done — Backend foundation (2026-08-24, earlier session)
- `Backend/` FastAPI project scaffolded: `app/{core,models,schemas,routers,services}`.
- All 11 SQLAlchemy models implemented exactly per the DB schema doc (see [[schema]]).
- Alembic set up, initial migration autogenerated and verified.
- `Backend/seed.py` — realistic sample data matching the UI prototype, safe to re-run.
- Verified end-to-end against a throwaway local Postgres: migrations + seed + FastAPI
  boot all confirmed working.

## Explicitly deferred (per task scope)
- Patient create/update/delete/search (only `GET /patients/{id}` + the AI-summary/
  notes actions exist — a doctor's roster now exists via
  `GET /doctors/{doctor_id}/patients`, but there's still no generic patient list/
  search/create endpoint; not asked for).
- Refresh tokens / logout / token revocation — not built, flagged as an MVP gap in
  [[decisions-log]].
- User `status` (Active/Invited) — no backing column in `users`, `PATCH
  /admin/users/{id}` only edits columns that actually exist; see [[decisions-log]].
- Frontend — was not started through every backend pass, per each task's scope at the
  time. The Flutter mobile app (patient/attendant role) is now built as of the
  2026-08-25 Flutter patient-app pass above; the React/Vite web app and Flutter
  doctor/admin screens are still not started.

## Open items needing your input before the next steps
- **Rule engine thresholds**: everything in `app/services/rules.py` not directly
  doc/prototype-sourced is a Claude Code proposal awaiting clinician-equivalent
  review — see the full breakdown in [[decisions-log]]. Worth a pass before this is
  demoed as authoritative.
- **Baseline formula**: the min/max -> mean±1sd progression in
  `app/services/baseline.py` is also a Claude Code proposal — see [[decisions-log]]
  for an observed characteristic (bands widen quickly on volatile history).
- **Acoustic-signal thresholds** (`app/services/audio_analysis.py`,
  `ACOUSTIC_FATIGUE_BREATHLESSNESS_POINTS` in `app/services/rules.py`): even less
  grounded than the rule-engine thresholds above — no training data, no clinician
  review, no real patient population comparison. See [[decisions-log]] for the full
  list of proposed numbers. Worth a pass before demoing the acoustic flag as
  meaningful, not just "doesn't crash."
- Postgres hosting choice (Railway add-on vs. Neon vs. Supabase) is still open per the
  schema doc's own "Open Items" section — not needed yet since `DATABASE_URL` is fully
  swappable, but will be needed before real deployment.
- **Blood pressure / blood sugar scoring (added 2026-09-07)**: `entries.systolic_bp`/
  `diastolic_bp`/`blood_sugar_mg_dl` are persisted and displayed to doctors, but
  deliberately NOT wired into `app/services/rules.py` yet — see [[decisions-log]] and
  [[schema]]. What counts as a hypertensive-crisis or hypoglycemia/hyperglycemia red
  flag varies by diagnosis and patient baseline, unlike weight's single doc-sourced
  threshold, so this needs its own clinician-equivalent threshold-review pass before
  these readings should affect `risk_level`/alerts — same discipline as the three
  items above.
- **Real-time push for messaging (added 2026-09-07)**: direct messaging currently
  polls `GET /patients/{id}/messages` every 12s on both platforms — this backend has
  no websocket/SSE infrastructure, and adding one was explicitly out of this pass's
  scope. Replacing polling with real-time push is a possible future upgrade, not a
  bug — see [[decisions-log]] and [[conventions]].

## Pre-deployment checklist (not needed now — don't lose track of these)
- [ ] Set a real `JWT_SECRET_KEY` via Railway env vars (or whichever host is chosen)
  before deploying. `app/core/config.py` currently defaults to an obviously-insecure
  dev string (`"insecure-dev-only-secret-change-me"`) — fine for local/hackathon dev,
  never acceptable in a deployed environment.
- [ ] Decide + provision the real Postgres host (Railway add-on vs. Neon vs. Supabase)
  and point `DATABASE_URL` at it.

## Not yet started
- Weekly digest generation/persistence (`weekly_digests` table still unused by real
  code — the Flutter "Trends" screen computes its own view client-side from
  timeline data instead, see the Flutter patient-app entry above).
- Patient create/update/search endpoints (see "Explicitly deferred" above); also
  still no `PATCH /patients/{id}` — the Flutter Profile screen is view-only.
- Nothing else — every role (patient/doctor/admin) is now built and
  verified on both platforms (Flutter and React web). See "PROJECT
  FEATURE-COMPLETE" at the top of this file.
