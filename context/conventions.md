# Conventions

## Backend folder structure
```
Backend/
  app/
    core/       # config.py (Settings/env incl. JWT), database.py (engine, SessionLocal,
                # Base, get_db), security.py (password hashing + JWT issue/verify),
                # deps.py (get_current_user, require_roles, get_authorized_patient,
                # get_authorized_doctor, get_clinician_patient — see RBAC section below)
    models/     # one SQLAlchemy model per file, snake_case filename = table name singular
                # models/__init__.py imports every model (required for Alembic autogenerate)
                # models/enums.py holds shared Python enums used by multiple models
    schemas/    # Pydantic request/response schemas — auth.py, patient.py, entry.py, ai.py,
                # doctor.py (roster/alerts/notes), admin.py (People & roles)
    routers/    # FastAPI routers — auth.py (/auth/login, /auth/me),
                # patients.py (/patients/{id}, POST /patients/{id}/ai-summary,
                # POST+GET /patients/{id}/notes — doctor/admin only, RBAC-protected),
                # entries.py (POST /entries with AI merge, GET /entries/{patient_id}/timeline,
                # POST /entries/{id}/audio — SEPARATE from POST /entries, see
                # decisions-log.md 2026-08-25 acoustic-analysis pass),
                # doctors.py (GET /doctors/{id}/patients, GET /doctors/{id}/alerts,
                # POST /alerts/{id}/review — two APIRouters in one file, see the file's
                # own docstring for why), admin.py (/admin/users CRUD, admin-only),
                # messages.py (POST+GET /patients/{id}/messages — direct messaging,
                # added 2026-09-07, `/patients` prefix like patients.py but split into
                # its own file since it's a large enough standalone feature — see below)
    services/   # rules.py (disease-specific red-flag + scoring engine — pure Python,
                # no AI, always runs), baseline.py (three-stage baseline_history
                # recompute — pure Python), ai.py (Claude API — symptom extraction +
                # summary generation, soft-fails to None on any error, never raises),
                # audio_analysis.py (numpy + system ffmpeg signal processing — NOT a machine-learning
                # model — pause/energy/pitch feature extraction from Voice Diary
                # recordings, soft-fails to None on any error, same contract as ai.py)
    main.py     # FastAPI app instance: /health + auth + patients + entries + doctors +
                # (alerts_router) + admin routers
  alembic/      # migrations; env.py imports app.core.config.settings for DATABASE_URL
  alembic.ini
  seed.py       # dev/demo seed script, safe to re-run (clears then re-inserts);
                # hashes a real shared demo password for every seeded user
  requirements.txt
  .env.example  # copy to .env for local dev
  .venv/        # gitignored
```

## Naming
- Table names: plural snake_case, exactly as in `docs/RozNoor_Database_Schema_and_Deployment_Plan.docx`
  (`users`, `patients`, `entries`, `entry_symptoms`, `symptom_checklist_options`,
  `ai_results`, `risk_results`, `baseline_history`, `alerts`, `doctor_notes`, `weekly_digests`).
- Model class names: singular PascalCase (`User`, `Patient`, `Entry`, `EntrySymptom`,
  `SymptomChecklistOption`, `AiResult`, `RiskResult`, `BaselineHistory`, `Alert`,
  `DoctorNote`, `WeeklyDigest`).
- Column names: snake_case, exactly as listed in the schema doc — do not rename or add
  columns without flagging it first (see CLAUDE task instructions / decisions-log.md).
- Enum Postgres type names: snake_case, e.g. `user_role`, `risk_level`, `entry_type`.
  Enum value casing: lowercase snake_case except `risk_level`, which keeps the doc's
  capitalized Green/Yellow/Orange/Red (see decisions-log.md).

## SQLAlchemy style
- SQLAlchemy 2.0 declarative style: `Mapped[...]` + `mapped_column(...)`, not the legacy
  `Column(...)` style.
- One model per file under `app/models/`; always add new models to `app/models/__init__.py`'s
  import list and `__all__` so Alembic autogenerate picks them up.
- Enums live in `app/models/enums.py` as `str, enum.Enum` subclasses, referenced via
  `sqlalchemy.Enum(MyEnum, name="pg_type_name")`.

## Config / DB connection
- All config comes from `app.core.config.settings` (pydantic-settings), reading
  `DATABASE_URL` (+ optional `.env`). Never hardcode a connection string elsewhere,
  including in `alembic/env.py` — it imports `settings` rather than reading `alembic.ini`'s
  `sqlalchemy.url` directly, so there is one source of truth.
- Expected `DATABASE_URL` shape: `postgresql+psycopg2://user:password@host:port/dbname`.

## Migrations
- Alembic, autogenerate-based. Run from `Backend/` with the venv active:
  `alembic revision --autogenerate -m "message"` then `alembic upgrade head`.

## Auth / RBAC
- Passwords: bcrypt via the `bcrypt` package directly (`app/core/security.py`
  `hash_password`/`verify_password`) — not passlib (version-compat issues), not
  argon2. Never store or log a plaintext password.
- Tokens: JWT (PyJWT), HS256, payload `{"sub": user_id, "role": role, "iat", "exp"}`,
  signed with `settings.jwt_secret_key`. 24h expiry, no refresh token in this MVP.
- Every protected route depends on `app.core.deps.get_current_user` (reads
  `Authorization: Bearer <token>`) — never re-implement token parsing per-router.
- Role gating: use `Depends(require_roles(UserRole.doctor, UserRole.admin))` (or
  similar) when a route should be restricted to specific roles outright.
- Patient-scoped data access: use `Depends(get_authorized_patient)` on any route with
  a `{patient_id}` path param — it both loads the `Patient` and enforces
  patient/attendant/doctor/admin ownership rules in one place. Don't hand-roll
  per-route ownership checks; extend `get_authorized_patient` instead if the rule needs
  to change.
- The ownership rule itself lives in `app.core.deps.is_authorized_for_patient(user,
  patient) -> bool`, factored out of `get_authorized_patient` so routes where
  `patient_id` comes from a request body instead of the URL (e.g. `POST /entries`) can
  reuse the same policy instead of duplicating it.
- Doctor-scoped resources (`GET /doctors/{doctor_id}/patients`,
  `GET /doctors/{doctor_id}/alerts`): `Depends(get_authorized_doctor)` — same
  shape as `get_authorized_patient` but for a `{doctor_id}` path param: admin
  always, doctor only for their own id, patient/attendant blocked entirely (not
  just narrowed — these routes have nothing for a patient/attendant to see).
  Boolean rule factored out the same way: `is_authorized_for_doctor`.
- Doctor/admin-ONLY, patient-scoped write routes (doctor notes, alert review):
  `Depends(get_clinician_patient)` (path-param version) or the underlying
  `is_authorized_clinician_for_patient(user, patient) -> bool` (for
  `POST /alerts/{id}/review`, where the path param is `alert_id` not
  `patient_id`, so the patient has to be resolved first). Deliberately excludes
  the patient/attendant self-access that `is_authorized_for_patient` allows —
  see [[decisions-log]] for why doctor_notes/alert-review are clinician-only
  even though the same patient can otherwise read their own record.
- **General pattern**: every new RBAC rule follows the same two-piece shape —
  a plain `is_authorized_for_X(user, resource_or_id) -> bool` function, plus a
  `get_authorized_X` (or narrower-named) FastAPI dependency that loads the
  resource, 404s if missing, and 403s via that boolean. Don't hand-roll a new
  ownership check inline in a router; add the pair to `app/core/deps.py`
  instead, even for a one-off case.
- **A variant, not a new pattern**: `is_authorized_to_send_message` (added
  2026-09-07 for direct messaging) follows the same shape but returns an enum
  (the `MessageSenderRole` to record) instead of a bool, since the router
  needs to know not just *whether* to allow the write but *which* role it's
  being made under. Read access still reuses the plain `get_authorized_patient`
  dependency unchanged — only the narrower write check needed a new function.
  See [[decisions-log]] for why admin is excluded from this one specifically.

## Direct messaging (`app/routers/messages.py`, added 2026-09-07)
No websocket infrastructure exists anywhere in this backend (it's REST-only,
confirmed by checking before building — see [[decisions-log]]) and none was
added for this feature. Both frontends implement it as polling instead: the
message screen re-fetches `GET /patients/{id}/messages` on a 12-second timer
while it's open, and stops when the screen is left (see the Flutter/React
sections below for how each platform's lifecycle makes that actually true,
not just intended). Real-time push (websockets/SSE) is flagged as a possible
future upgrade, not something this pass built — see [[progress]].

## Rules engine / baseline (app/services/)
- Every threshold/weight in `rules.py` and the baseline formula in `baseline.py` is
  either doc/prototype-sourced (cited inline) or an explicit Claude Code proposal
  flagged "NEEDS REVIEW" — see [[decisions-log]] for the full breakdown. Don't add a
  new numeric threshold without the same citation-or-flag treatment.
- `evaluate_entry()` itself always returns `source=RiskSource.rule` — the caller
  (`app/routers/entries.py`) is what upgrades this to `'merged'` when the AI step
  actually ran. `rules.py` has no knowledge of AI and must stay that way — it's the
  fallback layer and must work with zero dependency on `app.services.ai`.
- Rule evaluation must run against baseline bands as they stood BEFORE the new entry
  (fetch `baseline_history` prior to calling `update_baseline_after_entry`) — never
  evaluate an entry against a band it has already been folded into.
- Diagnosis is free text, not an enum — rule-set lookup is a case-insensitive
  substring match (`app.services.rules.diagnosis_key`, public — also reused by
  `app.services.ai` and the entries router to scope which checklist symptoms AI is
  allowed to match against, via `CHECKLIST_DIAGNOSIS_SEARCH_TERMS`), with an explicit
  diagnosis-agnostic fallback ruleset for anything unrecognized, not an error.
- Not every tracked metric belongs in the generic "below baseline_min is bad"
  deviation loop (`_METRIC_COLUMNS` in `rules.py`) — `weight` is deliberately excluded
  because a RISE, not a dip, is the danger signal for heart failure. It still gets a
  `baseline_history` band via `baseline.py`'s own `METRIC_COLUMNS` (a separate dict,
  for charting), just evaluated by its own dedicated red-flag check instead. Before
  adding a new metric to either dict, check which direction of deviation is actually
  the risk signal for it.

## AI layer (app/services/ai.py)
- Every public function is soft-fail: return `None` on any error (missing key,
  network failure, API error, timeout, schema-validation failure) — **never raise**.
  Callers must always have a working rule-only path; see `app.core.config.settings`
  for the API key and the module's own docstring for the full fallback contract.
- `rules.py`/`baseline.py` never import from `ai.py` — dependency direction is
  one-way (AI feeds evidence into the rule engine's inputs; the rule engine itself
  stays AI-agnostic). Never make `rules.py` depend on this module.
- AI-extracted symptoms are validated against the actual checklist before being
  trusted (`extract_symptoms()` filters `matched_symptoms` down to names that are
  literally in the provided `checklist_names` list) — never pass an AI-returned
  string straight into a DB lookup or the rule engine without that filter.
- Numbers (`deviation_deltas`) are computed in plain Python from data the rule engine
  already has, never phrased/computed by Claude — only free-text interpretation
  (`extracted_symptom_tags`) is genuinely AI-derived. Keep it that way; don't let
  Claude restate a number that's already known exactly.
- Model: `claude-opus-5` (current Anthropic default, no reason for this app to
  downgrade). Uses `client.messages.parse(output_format=PydanticModel)` for
  extraction (structured output, guaranteed-valid JSON) and plain
  `client.messages.create()` for the free-text summary.

## Acoustic analysis (app/services/audio_analysis.py)
Added 2026-08-25. **Pure signal processing via numpy + a system `ffmpeg` subprocess
(for decoding) — NOT a machine-learning model, and deliberately NOT librosa.** Built
on librosa first, then rewritten mid-pass after `pip install librosa` repeatedly
failed to complete against this sandbox's actual (very slow) network — see
[[decisions-log]] for the full story and the real bug that a hand-rolled
implementation, tested for real, caught before shipping. `ffmpeg` must be on PATH at
runtime — a real, separate requirement from the Python dependencies. No training data
exists for this project and building/fitting one was explicitly out of scope; every
feature is a directly-computed statistic (pause ratio, frame-energy variance, pitch
variability) and every derived flag is a hand-picked threshold on those statistics,
same rule-based spirit as `app/services/rules.py`.
- Same soft-fail contract as `app/services/ai.py`: `extract_acoustic_features()`
  returns `None` on any error (missing/corrupt file, `ffmpeg` missing, numpy not
  importable, too-short/silent recording) — never raises. Callers must treat `None`
  as "acoustic analysis unavailable" and leave the entry's existing (transcript-only)
  risk_result untouched.
- **`numpy` is imported lazily, function-local, NOT at module level** —
  a module-level import would crash `app.main` at startup (this module is imported
  unconditionally by `app/routers/entries.py`) if the package failed to install,
  taking down the entire backend including the unrelated transcript-only path. Caught
  during this pass's own verification before it shipped — see `context/decisions-log.md`.
  Any future heavy/optional dependency added to this module must follow the same
  lazy-import pattern.
- Feeds into `app/services/rules.py`'s Layer-B (weighted score) ONLY, via
  `evaluate_entry()`'s optional `acoustic_flag`/`acoustic_detail` params — can NEVER
  trigger a hard Layer-A red flag on its own (see `ACOUSTIC_FATIGUE_BREATHLESSNESS_POINTS`
  in `rules.py`), since these thresholds have even less evidence backing them than the
  rest of that file's already-flagged proposed weights.
- Called from a SEPARATE endpoint (`POST /entries/{id}/audio`), not from
  `POST /entries` itself — see the entries.py section above and
  `context/decisions-log.md` for why. Every threshold in this module is a Claude Code
  proposal needing review — see the module's own docstring for the full rationale.

## Flutter app (`mobile_app/`) — patient/attendant role

### Folder structure
```
mobile_app/
  lib/
    core/       # app_config.dart (API base URL), api_client.dart (Dio + auth
                # interceptor + ApiException/run() wrapper), secure_storage.dart
                # (flutter_secure_storage wrapper), theme.dart (RnColors — the
                # prototype's Sage/Paper light palette — + RnDarkColors — the
                # prototype's Nocturne dark palette, added 2026-08-27 — +
                # buildRnLightTheme()/buildRnDarkTheme() + the context.rnMuted()
                # theme-aware secondary-text extension, see below)
    models/     # plain Dart classes with fromJson, one per api-contracts.md
                # response shape (AuthSession, PatientProfile, Entry, RiskResult,
                # SymptomOption) — no codegen, this app's API surface is small
    services/   # AuthService, PatientService, EntryService (incl. uploadAudio, added
                # 2026-08-25) — one per api-contracts.md section, each a thin wrapper
                # with NO business logic of its own (see "API client pattern" below);
                # AudioRecorderService (added 2026-08-25) is the one exception — it
                # wraps the `record` plugin, not a backend endpoint, see below
    state/      # ChangeNotifier providers — AuthProvider (session + login/logout/
                # restore), LanguageProvider (EN/Roman Urdu toggle, non-persistent —
                # see decisions-log), PatientDataProvider (profile/checklist/
                # timeline, shared across the patient shell so a submitted entry
                # updates Home/Timeline/Digest without each screen re-fetching),
                # ThemeProvider (Paper/Nocturne ThemeMode, PERSISTS via
                # shared_preferences — added 2026-08-27, see below)
    screens/
      auth/login_screen.dart      # ONE form for both patient and clinician entry
                                   # points — see "no duplicate auth logic" below
      root_router.dart            # the ONLY place that decides post-login routing,
                                   # from session.role alone — see decisions-log
                                   # ("role-switcher removal")
      placeholder_screen.dart     # doctor/admin landing until those screens exist
      patient/                    # Home, VoiceDiary, QuickCheckin, Result,
                                   # Timeline, WeeklyDigest, Profile
    widgets/    # BilingualText, RiskBadge/RiskDot, PatientShell (bottom-tab shell:
                # Home/Speak/Timeline/Trends — Quick Check-in/Result/Profile are
                # pushed on top, not additional tabs, matching the prototype)
    main.dart   # MultiProvider + MaterialApp, home: RootRouter
  scripts/
    gen_app_icon.py  # generates assets/icon/app_icon*.png (Python + Pillow) —
                      # re-run after changing the icon concept, then re-run
                      # `dart run flutter_launcher_icons` — see the Icon section below
  assets/icon/   # app_icon.png (1024x1024 master) + app_icon_foreground.png
                 # (transparent-bg, Android adaptive-icon foreground layer) —
                 # flutter_launcher_icons input, not runtime-loaded assets
```

### State management: Provider (`ChangeNotifier`)
Not Riverpod/Bloc — three small providers, no complexity that would justify a
heavier framework. See [[decisions-log]].

### API client pattern
One shared `Dio` instance (`ApiClient.instance.dio`) with a single interceptor
that reads the JWT from `SecureStorageService` and attaches
`Authorization: Bearer <token>` to every request — no screen or service builds
that header itself. `ApiClient.instance.run(() => ...)` wraps every service
call and turns any failure into an `ApiException(statusCode, message)` using
the backend's `detail` field, so screens catch one exception type and show a
human-readable message. Every `*Service` class matches exactly one
`api-contracts.md` section and does nothing else — no service re-implements
auth, error parsing, or business logic that belongs in a provider or the
backend.

### Secure storage: `flutter_secure_storage`
Not `SharedPreferences` (task instruction). Stores only `token`/`userId`/
`role`/`name` for cold-start restore; `patient_id`/`language_preference` are
always re-fetched live via `GET /auth/me` on restore rather than cached, so a
stale role can never drive routing decisions.

### Role-switcher tabs: removed / never built
The Patient/Doctor/Admin radio-button switcher in the design prototype
(`UI Inspo/.../RozNoor.dc.html`) is a preview tool for that mockup file only
and was never present in any shippable code — confirmed by searching the repo
before building anything (see [[decisions-log]], 2026-08-25). The Flutter app
has no such control: `lib/screens/root_router.dart` decides post-login
routing purely from `session.role` (sourced from the backend JWT), and
`login_screen.dart`'s primary-vs-clinician entry points differ only in
copy/color, never in which endpoint is called or how the response routes.
**When building the React web app in a later phase, apply the same rule**:
if a role-switcher-shaped control shows up while adapting the prototype,
leave it out and route by JWT role instead — don't reintroduce it.

### Running the phone app on the real backend over LAN
Needed to test on a real device/emulator (not just Linux desktop) — three
separate requirements, all confirmed 2026-08-25 (see [[decisions-log]]):
1. **Backend must run with `--host 0.0.0.0`**, not the default:
   `uvicorn app.main:app --host 0.0.0.0 --port 8000`. The default (or
   `--host 127.0.0.1`) binds to loopback only — invisible to any other
   device on the network even though `curl localhost:8000` from the dev
   machine itself looks fine.
2. **Point the app at the dev machine's actual LAN IP**, not `localhost` —
   `AppConfig.apiBaseUrl` (`lib/core/app_config.dart`) is already
   `--dart-define`-configurable for exactly this reason:
   `flutter run --dart-define=ROZNOOR_API_BASE_URL=http://<dev-machine-LAN-IP>:8000`.
   Find the IP with `hostname -I` (the WiFi/LAN interface — e.g. `wlo1` —
   not a `docker0`/`br-*` bridge address). It's DHCP-assigned and can
   change on reconnect; re-check if a previously-working setup stops
   connecting. An Android *emulator* (not a real device) instead uses the
   fixed alias `10.0.2.2` for the host's `localhost`.
3. **Android blocks plain-HTTP traffic by default** for apps targeting
   API 28+ — the backend has no TLS, so without an explicit opt-in every
   request from a real device fails with `CLEARTEXT communication ... not
   permitted`, regardless of whether the IP/port are correct. Handled via
   `android/app/src/debug/res/xml/network_security_config.xml`
   (`cleartextTrafficPermitted="true"`, debug builds only — wired in via
   that same folder's `AndroidManifest.xml`); a release build stays on
   the strict default. Don't touch `src/main/`'s network policy to work
   around this — the debug-only scoping is deliberate.

### Plugin platform permissions are a build-time checklist item
When adding a plugin that touches a device capability (mic, camera,
location, contacts, etc.), check its own README/platform setup docs for
required `AndroidManifest.xml`/`Info.plist` entries **as part of adding the
plugin** — don't defer this to whenever a test environment happens to have
the matching hardware to exercise it live. A test environment lacking mic
hardware (this project's original dev sandbox) will make a missing
`RECORD_AUDIO` permission and a missing microphone look identical (both
report "speech unavailable, fall back to typing") — the manifest check has
to happen independent of what a given environment can actually verify live.
Case in point: `speech_to_text` needs `RECORD_AUDIO`, `INTERNET`,
`BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_CONNECT`, plus a `<queries>`
entry for `android.speech.RecognitionService` on `targetSdk` 30+ (all in
`android/app/src/main/AndroidManifest.xml`, not a debug-only overlay — a
real/production app needs the mic permission unconditionally) — missed
during the original build, only caught once a real device with a mic
exposed it. See [[decisions-log]]. Its `initialize()` call already handles
the runtime permission *request* itself (native `ActivityCompat.
requestPermissions()`) — no separate Dart-side request call needed once the
manifest declares the permission.
**A permission added to the manifest after an app is already installed on a
device needs a full uninstall + reinstall, not a hot reload** — Android
reads `<uses-permission>` at install time from the APK.

### Voice Diary raw audio capture (added 2026-08-25) — runs concurrently with speech_to_text, unverified real-device risk
`lib/services/audio_recorder_service.dart` wraps the `record` package to capture the
raw waveform **at the same time as** `speech_to_text`'s live-transcript mic session
(Voice Diary needs both: the transcript for the existing text-based rule/AI path, the
raw audio for `app/services/audio_analysis.py`). `RECORD_AUDIO` is already declared
(see above), so no new Android permission was needed, but two components requesting
mic access simultaneously is itself a genuine, device/OEM-dependent risk this sandbox
cannot verify (no microphone hardware here). Handled by making every recorder method
non-throwing best-effort (`start()`/`stop()` return `false`/`null` on any failure
rather than raising) — a failure here silently means the entry submits transcript-only,
exactly as it always has; it must never surface as a broken Voice Diary. See
[[decisions-log]]. **Needs the user's own real-device test** to confirm concurrent
capture actually works end-to-end.

### Paper/Nocturne theme (added 2026-08-27)
`lib/state/theme_provider.dart` — `ThemeProvider extends ChangeNotifier`,
holds a plain `ThemeMode` and persists it via `shared_preferences`
(new dependency; NOT `flutter_secure_storage` — a display preference
isn't a secret, unlike the JWT that package is reserved for). Defaults to
Paper (light) on first launch, matching the prototype's own default.
Wired into `MaterialApp` in `main.dart` via `darkTheme:
buildRnDarkTheme()` + `themeMode: themeProvider.mode`. Toggle UI lives on
the Profile screen (`SegmentedButton`, "Paper"/"Nocturne", next to the
Roman Urdu switch) — no other screen has theme-switching UI.
- `RnDarkColors` (`lib/core/theme.dart`) is a direct port of the
  prototype's real `#rn[data-theme="dark"]` values (`RozNoor.dc.html`),
  same as `RnColors` for light — never invent new dark-mode colors here,
  pull them from the prototype's CSS block the way the light palette was.
- **`context.rnMuted([alpha])`** (extension on `BuildContext`, same file)
  is the theme-aware replacement for the `Colors.black.withValues(alpha:
  ...)` pattern used for secondary/muted text — that pattern stays
  literally black regardless of theme and goes unreadable against
  Nocturne's dark backgrounds (a real bug found and fixed across ~20 call
  sites in 9 screens while adding this theme — see [[decisions-log]]).
  **Never add a new `Colors.black.withValues(...)` secondary-text style
  anywhere in this app — use `context.rnMuted()` instead.**
- `RiskBadge`/`RiskDot` (`RnColors.forRiskLevel`) and a few fixed brand
  colors (e.g. `RnColors.riskRed` on the Emergency button) are
  deliberately NOT theme-switched — they keep their light-mode ink in
  both themes. Confirmed to still read fine against Nocturne surfaces;
  don't "fix" this without a reason, it's an intentional simplification,
  not an oversight.

### App launcher icon (added 2026-08-27)
No design asset exists for this app — the icon is generated
programmatically (`mobile_app/scripts/gen_app_icon.py`, Python + Pillow),
not hand-designed, and applied via `flutter_launcher_icons` (dev
dependency, config block in `pubspec.yaml`). Current concept: a stylized
teal heartbeat/pulse glyph (a leaf/sapling concept was also generated and
shown to the user, and NOT picked — see [[decisions-log]] for why).
- To change the icon: edit `scripts/gen_app_icon.py`, run `python3
  scripts/gen_app_icon.py` from `mobile_app/` to regenerate
  `assets/icon/app_icon.png` (1024x1024 master, used directly for iOS)
  and `assets/icon/app_icon_foreground.png` (transparent background, used
  as the Android adaptive-icon foreground layer — pulled further inward
  than the master since Android's adaptive mask crops roughly the outer
  third), then run `dart run flutter_launcher_icons` to regenerate every
  platform size/file. Always show the user the result before treating a
  changed icon as final — per the original task's explicit ask, this
  isn't a one-way door.
- `remove_alpha_ios: true` in the `flutter_launcher_icons` pubspec.yaml
  config is required — Apple rejects icons with an alpha channel.
  `adaptive_icon_background: "#0F6B68"` (matches `RnColors.accent`) is the
  Android adaptive-icon background layer, kept in sync with the
  foreground glyph's own teal gradient in the iOS/legacy master icon.
- **Not verified on an actual Android/iOS device or emulator** — no SDK
  license accepted / no emulator available in this sandbox. Verified
  instead by rendering the actual generated
  `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (not just the
  source PNG) — see [[decisions-log]].

### Doctor screens (built 2026-08-29) — design source, folder structure
The doctor role is now built; admin is still the only role left on
`lib/screens/placeholder_screen.dart`. **Design source used**: the web
prototype's `d-patients`/`d-detail`/`d-alerts` (`UI Inspo/.../RozNoor.dc.html`),
adapted to mobile stacked cards + a bottom sheet (for add-note) instead of
the prototype's table rows/sidebar — confirming the plan already recorded
in this file (see the entry above, now superseded) held for this pass.
`a-people` (admin) is unbuilt — out of this session's scope.

```
lib/
  models/doctor.dart       # DoctorPatientRosterItem, AlertItem, DoctorNote —
                            # mirror app/schemas/doctor.py exactly, see
                            # context/api-contracts.md
  services/doctor_service.dart  # GET /doctors/{id}/patients,
                            # GET /doctors/{id}/alerts,
                            # POST /alerts/{id}/review — one file since all
                            # three are one doctor-workflow surface,
                            # mirroring app/routers/doctors.py's own
                            # two-router-one-file grouping
  services/patient_service.dart  # extended with GET/POST
                            # /patients/{id}/notes — kept here (not in
                            # DoctorService) since api-contracts.md groups
                            # /patients/{id}/notes under "Patients", same
                            # URL prefix as this file's other two methods,
                            # even though only doctor/admin can reach it
                            # (RBAC is backend-side)
  state/doctor_data_provider.dart  # DoctorDataProvider — roster + alerts
                            # (loaded together in loadAll(doctorId)) plus
                            # per-patient detail state (profile/timeline/
                            # notes, loaded on demand via
                            # loadPatientDetail(patientId)). Mirrors
                            # PatientDataProvider's shape/conventions.
  widgets/doctor_shell.dart  # bottom-tab shell: Patients / Alerts (d-detail
                            # is reached by tapping a patient, not a tab —
                            # matches the prototype's own nav structure)
  widgets/trend_chart.dart  # hand-rolled CustomPainter line chart, no new
                            # charting package — see the note below
  screens/doctor/
    patient_roster_screen.dart  # doctor home — GET /doctors/{id}/patients,
                            # client-side search-filter over the loaded list
    patient_detail_screen.dart  # timeline (GET /entries/{patient_id}/
                            # timeline, same endpoint the patient app
                            # calls) + trend charts + alert history + notes
                            # (view + add via a bottom sheet)
    alerts_screen.dart      # GET /doctors/{id}/alerts + POST
                            # /alerts/{id}/review, Unread/All segmented
                            # filter
```

**No baseline-band chart — a real backend-scope gap, not an oversight.**
The prototype's d-detail Sleep/Weight cards shade a "learned normal" band
behind the line (from `baseline_history.baseline_min/max`), but no
endpoint exposes that table to a client (checked `api-contracts.md` in
full before building — there is genuinely none). `TrendChart` instead
plots the patient's actual recorded values over time from the timeline
entries already being fetched — real trend data, just not a baseline band.
Flagged to the user as a task-scope note (backend was described as
already complete for this session) rather than silently adding a new
backend endpoint outside the session's stated scope — see
[[decisions-log]].

**RBAC used, no new backend dependencies added**: `doctor_id` passed to
`DoctorService` calls is the doctor's own `session.userId` (not a separate
"doctor profile id" — `assigned_doctor_id` on `patients` references
`users.id` directly, confirmed against [[schema]]).

### Admin screens (built 2026-08-29, later same day) — design source, folder structure, smallest remaining scope
The admin role is now built — this completes all three roles on Flutter
(patient/doctor/admin). **Deliberately the smallest possible scope, per
the task's explicit instruction**: one screen (People & roles: list,
create, edit) and no complex workflows — no rule-set management, no
bulk actions, no password-reset flow (the backend has none — see
`PATCH /admin/users/{id}` in [[api-contracts]]). **Design source used**:
the web prototype's `a-people` screen (`UI Inspo/.../RozNoor.dc.html`),
adapted to mobile stacked cards instead of a table row grid — same
adaptation pattern the doctor role's `patient_roster_screen.dart` used
for `d-patients`. The prototype's "Red-flag rule sets" card at the
bottom of `a-people` is decorative demo dressing with no backing data
(no endpoint exposes rule-set versions/review dates) — left out rather
than faked, same spirit as the doctor role's baseline-band-chart
omission (see [[decisions-log]]).

```
lib/
  models/admin_user.dart        # AdminUser — mirrors AdminUserOut
                                 # (app/schemas/admin.py) exactly, see
                                 # context/api-contracts.md. Deliberately
                                 # no `status` field — `users` has none.
  services/admin_service.dart   # GET/POST /admin/users,
                                 # PATCH /admin/users/{id} — one file,
                                 # mirrors doctor_service.dart's
                                 # one-file-per-role-workflow grouping
  state/admin_data_provider.dart # AdminDataProvider — users list,
                                 # loadAll()/refresh(), createUser/
                                 # updateUser update the list in place
                                 # afterward rather than re-fetching
                                 # (mirrors DoctorDataProvider's
                                 # reviewAlert/addNote convention)
  screens/admin/
    people_screen.dart          # admin home — GET /admin/users,
                                 # client-side search-filter, FAB
                                 # "Invite a person" -> create form,
                                 # tap a row -> edit form
    user_form_screen.dart       # ONE form for both create (POST) and
                                 # edit (PATCH) — existing: null selects
                                 # create mode. No password field in
                                 # edit mode (backend doesn't support
                                 # changing it) — flagged inline in the
                                 # form itself, not silently omitted.
```

No `AdminShell`/bottom-tab widget — unlike `DoctorShell`, there's only
one admin screen this session, so `RootRouter` routes `role == 'admin'`
straight to `PeopleScreen`, with its own once-per-sign-in
`AdminDataProvider.loadAll()` guard (same shape as the doctor branch
added in the 2026-08-29 doctor-role pass) and its own `reset()` call on
the `signedOut` transition (extending the same fix that pass made to
`root_router.dart` for the account-switch bug — see [[decisions-log]]).
`lib/screens/placeholder_screen.dart` is now genuinely dead code (every
real role has its own screen) — kept only as a structural fallback, not
routed to by any real backend role value.

**No new backend dependencies, no schema changes** — `GET/POST
/admin/users` and `PATCH /admin/users/{id}` were already complete and
verified in the 2026-08-25 doctor & admin routers pass; this session
only builds the Flutter client against them.

### Direct messaging (added 2026-09-07) — shared chat screen, both roles
`lib/models/message.dart` (mirrors `MessageOut`), `lib/services/message_service.dart`
(GET/POST `/patients/{id}/messages`), and `lib/screens/messages_screen.dart` — the
last one lives at the **top level** of `screens/`, not under `patient/` or `doctor/`,
since the chat UI genuinely doesn't differ by role: `MessagesScreen(patientId, title)`
is reached from the patient Home screen (a new `_NavCard`, title = the assigned
doctor's name) and from the doctor's `patient_detail_screen.dart` (a new app-bar
"Messages" icon, title = the patient's name). Which bubbles render right-aligned is
derived purely from `message.senderUserId == session.userId`, which works identically
for either caller — no role-specific branching needed anywhere in the screen itself.

**Reached by pushing on top of a shell (like Profile/Quick Check-in), deliberately NOT
a `PatientShell`/`DoctorShell` `IndexedStack` tab** — an `IndexedStack` keeps every
tab's widget state alive even when not visible, which would keep a `Timer.periodic`
poll running in the background after the user switches tabs, directly violating the
task's "stop polling when the screen is left" requirement. A pushed screen's
`dispose()` genuinely cancels the timer when the user navigates away, so this was a
deliberate navigation-pattern choice, not just a styling one — see [[decisions-log]].

State is local `StatefulWidget` state (a `Timer.periodic` re-fetch every 12s,
cancelled in `dispose()`), not folded into `PatientDataProvider`/`DoctorDataProvider`
— messages aren't needed anywhere else in the app the way profile/timeline/roster
data is shared across multiple screens, so a dedicated provider would add
indirection with no reuse benefit.

## React web app (`web_app/`) — patient/attendant role, built 2026-08-29

Vite + React (JavaScript, no TypeScript — matches `mobile_app`'s own "no
codegen, this app's API surface is small" reasoning for skipping a typed
model layer, see that section above), same backend, same patient screens
as `mobile_app/`, no doctor/admin screens yet (next session's scope — see
[[progress]]). Built by mirroring `mobile_app/lib/` file-for-file where a
web equivalent exists, adapted where the platform genuinely differs (JWT
storage, speech capture, CORS) — see [[decisions-log]] for each of those.

### Folder structure
```
web_app/
  src/
    core/         # appConfig.js (API base URL), apiClient.js (fetch wrapper +
                   # ApiException + auth header injection — mirrors
                   # mobile_app's ApiClient), tokenStorage.js (JWT
                   # persistence — see decisions-log for why localStorage,
                   # not an httpOnly cookie), theme.css (Paper/Nocturne CSS
                   # custom properties, same hex values as mobile_app's
                   # RnColors/RnDarkColors), riskColors.js, patientProfile.js
                   # (baselineStageLabel/medicationList — mirrors the
                   # getters on mobile_app's PatientProfile model)
    services/      # authService.js, patientService.js, entryService.js —
                   # one per api-contracts.md section, same shape as
                   # mobile_app's *Service classes, no business logic of
                   # their own
    state/         # React Context + hooks, one per mobile_app ChangeNotifier:
                   # AuthContext (useAuth), LanguageContext (useLanguage),
                   # ThemeContext (useTheme), PatientDataContext
                   # (usePatientData)
    components/    # BilingualText, RiskBadge/RiskDot, PatientShell (sidebar
                   # nav + <Outlet/>, prototype's actual desktop aside.rn-side
                   # layout — see below), EmergencyModal
    screens/
      auth/LoginScreen.jsx
      patient/     # Home, VoiceDiary, QuickCheckin, Result, Timeline,
                   # WeeklyDigest, Profile — one file each, same screen set
                   # as mobile_app/lib/screens/patient/
      PlaceholderScreen.jsx  # doctor/admin landing, mirrors
                              # mobile_app/lib/screens/placeholder_screen.dart
    App.jsx        # role-based routing — mirrors root_router.dart exactly,
                    # see its own doc comment
    main.jsx       # provider tree + BrowserRouter
  vite.config.js   # dev-server proxy — see decisions-log
```

### Routing: React Router, role-gated purely by JWT, same as Flutter
`App.jsx` is the *only* place that decides which screens a signed-in user
can reach, deciding purely from `session.role` — same "no role-switcher,
routing is never a user choice" rule as `mobile_app/lib/screens/root_router.dart`
(see [[decisions-log]], "role-switcher removal"). A patient/attendant gets
the `<PatientShell/>` route tree; anyone else (doctor/admin) gets
`PlaceholderScreen` regardless of URL. The just-submitted `Entry` is passed
to the Result screen via React Router's `location.state` (not re-fetched),
mirroring Flutter passing the `Entry` object straight through `Navigator`.

### State management: React Context + hooks, not Redux/Zustand
Same "small app, no complexity that would justify a heavier framework"
reasoning `mobile_app` gave for picking Provider over Riverpod/Bloc — four
small contexts, each mirroring one Flutter `ChangeNotifier` 1:1 (see
folder structure above).

### Nav shell: prototype's actual desktop sidebar, not mobile's bottom-tab adaptation
`mobile_app/lib/widgets/patient_shell.dart` adapted the prototype's
`aside.rn-side` desktop sidebar into a phone bottom-tab bar (a phone has no
room for a sidebar). `PatientShell.jsx` uses the prototype's real sidebar
layout directly — a web app has the room the phone didn't, so no
adaptation was needed here the way it was for mobile.

### Theme: Paper/Nocturne via CSS custom properties + `[data-theme]`, persisted
`theme.css`'s `:root` (light) / `html[data-theme="dark"]` (Nocturne)
blocks carry the SAME hex values as `mobile_app/lib/core/theme.dart`'s
`RnColors`/`RnDarkColors` — both ultimately sourced from the prototype's
`#rn`/`#rn[data-theme="dark"]` CSS block, so all three surfaces (prototype,
mobile, web) render the identical brand palette. `ThemeContext` toggles
`data-theme` on `<html>` and persists the choice to `localStorage` — same
persistence *intent* as `ThemeProvider`'s `shared_preferences` use (a pure
client display preference, no server-side "account truth" to reconcile
against, so persisting locally is unambiguously correct — same reasoning,
different storage API). Risk badge colors are (deliberately, same as
Flutter) NOT re-defined for dark — they keep their light-mode ink in both
themes; confirmed to still read fine against Nocturne on web too (see
[[decisions-log]] verification narrative).

### Language toggle: exclusive, non-persistent, same contract as Flutter
`BilingualText` renders exactly one of `en`/`ur` — built exclusive from the
start (see its own doc comment) rather than needing the same fix
`mobile_app/lib/screens/auth/login_screen.dart` needed on 2026-08-27.
`LanguageContext` is deliberately NOT persisted (no `localStorage`) for the
same reason `LanguageProvider` isn't: there's no `PATCH` endpoint to
reconcile a toggle back to the account's stored `language_preference`, so
persisting a client-side override would risk it silently diverging from
account truth across sessions. It resets to the account's stored
preference on every fresh sign-in/page load (`setFromAccountPreference` in
`App.jsx`'s effect, mirroring `root_router.dart`'s own call site) and stays
in-session-only otherwise — including across logout within the same tab,
same as Flutter's documented (not accidental) behavior.

### Voice Diary (`VoiceDiaryScreen.jsx`) — Web Speech API + MediaRecorder, NOT speech_to_text/record
See the file's own extensive doc comment for the full write-up. Short
version: transcription uses the browser's `SpeechRecognition`/
`webkitSpeechRecognition` (Chrome/Edge only, cloud-based in Chrome, needs
HTTPS in production — real, flagged differences from `mobile_app`'s
on-device `speech_to_text`), with the exact same typed-text fallback
contract (`POST /entries` called identically either way). The
acoustic-analysis raw-audio sample uses `MediaRecorder` (via
`getUserMedia`), captured SEQUENTIALLY after speech recognition ends —
mirroring `mobile_app`'s 2026-08-27 mic-contention fix proactively, even
though browsers may not share that exact contention risk (not verified
either way — see [[decisions-log]]). The recorded `audio/webm` Blob is
uploaded via `POST /entries/{id}/audio` exactly like Flutter's `.m4a` file
— **acoustic-analysis audio upload IS feasible on web**, not skipped; the
task brief's flagged uncertainty about this turned out resolvable, not a
real gap. **Not live-verified with a real microphone this session** — no
audio input hardware in the sandboxed browser environment used for
verification (same category of gap `mobile_app` had before real-device
testing) — see [[pending-device-tests]].

### CORS: dev-server proxy, not backend CORS middleware
The FastAPI backend has no CORS middleware (checked before building
anything) and none was added — a backend change outside this session's
explicit "no backend changes" scope. `vite.config.js`'s `server.proxy`
forwards every backend path to `http://localhost:8000` server-side, so the
browser only ever makes same-origin requests. See [[decisions-log]] for
the full reasoning, including the production-deployment caveat (this proxy
is dev-server-only; a production build needs either backend CORS or a
reverse-proxy layer in front, neither built this session).

### JWT storage: `localStorage`, not an httpOnly cookie
See [[decisions-log]] ("JWT storage on web") for the full reasoning — an
httpOnly cookie (the safer browser-native option) isn't available without
a backend change (`POST /auth/login` returns the token in a JSON body
only, never sets `Set-Cookie`), which is out of this session's scope.
`localStorage` was picked over `sessionStorage`/in-memory-only so a
signed-in patient stays signed in across a closed tab/restart, matching
`mobile_app`'s actual persisted-session behavior — the real XSS trade-off
this carries is flagged plainly in `src/core/tokenStorage.js`'s own doc
comment, not silently accepted.

## React web app (`web_app/`) — doctor role, built 2026-08-29 (later same day)

Mirrors `mobile_app/lib/`'s doctor section (roster, patient detail, alerts
panel) against the same unmodified backend, adapted to the prototype's
actual desktop table/two-column layout rather than mobile's stacked cards
— same "a web app has the room a phone doesn't" reasoning the patient-role
`PatientShell` sidebar already used. Full build/verification narrative in
[[decisions-log]]; this is the structural/file reference.

### New/changed files
```
web_app/
  src/
    services/
      doctorService.js      # GET /doctors/{id}/patients, GET /doctors/{id}/alerts,
                             # POST /alerts/{id}/review — mirrors
                             # mobile_app/lib/services/doctor_service.dart
      patientService.js     # extended with getNotes/addNote
                             # (GET/POST /patients/{id}/notes) — kept here,
                             # not doctorService.js, same reasoning as the
                             # Flutter file's own doc comment
                             # (api-contracts.md groups /patients/{id}/notes
                             # under "Patients")
    state/
      DoctorDataContext.jsx # useDoctorData() — mirrors
                             # mobile_app/lib/state/doctor_data_provider.dart's
                             # shape exactly: roster + alerts loaded together
                             # via loadAll(doctorId), per-patient detail
                             # state (profile/timeline/notes) loaded on
                             # demand via loadPatientDetail(patientId),
                             # reviewAlert/addNote update already-loaded
                             # lists in place rather than re-fetching
    components/
      DoctorShell.jsx        # sidebar nav shell — Patients / Alerts (with a
                              # live unread-count badge), matching the
                              # prototype's own two sidebar items; patient
                              # detail is reached by clicking a row, not a
                              # nav item of its own, same as
                              # mobile_app's DoctorShell bottom-tab structure
      TrendChart.jsx          # hand-drawn SVG line chart, no charting
                              # library — mirrors
                              # mobile_app/lib/widgets/trend_chart.dart's
                              # CustomPainter equivalent and the
                              # prototype's own hand-drawn SVG polylines
    screens/doctor/
      PatientRosterScreen.jsx # GET /doctors/{id}/patients — searchable
                              # table (name/MR number), "N monitored · N
                              # need attention" count, risk-colored left
                              # border per row — content/layout source:
                              # the prototype's d-patients screen
      PatientDetailScreen.jsx # timeline (GET /entries/{patient_id}/
                              # timeline, same endpoint the patient app
                              # calls) + raw-value trend charts (weight/
                              # sleep, only rendered when >=2 points exist)
                              # + alert history + doctor notes (view + add,
                              # inline form not a modal — a web-appropriate
                              # adaptation of mobile's bottom sheet).
                              # Content/layout source: the prototype's
                              # d-detail screen (two-column layout)
      AlertsScreen.jsx        # GET /doctors/{id}/alerts + POST
                              # /alerts/{id}/review, Unread/All toggle —
                              # content/layout source: the prototype's
                              # d-alerts screen
    App.jsx                  # extended: session.role === 'doctor' gets
                              # <DoctorShell/> route tree instead of
                              # PlaceholderScreen (admin still gets the
                              # placeholder — separate future scope); a
                              # second data-load effect, keyed on
                              # session.userId via useRef (NOT a fire-once
                              # boolean — see decisions-log.md for the real
                              # Flutter bug this avoids by construction),
                              # reloads doctor roster/alerts on every
                              # doctor sign-in
    main.jsx                 # wrapped in <DoctorDataProvider>
```

### Routing: `/roster`, `/roster/:patientId`, `/notifications` — deliberately NOT `/patients`/`/alerts`
`vite.config.js`'s dev-server proxy forwards the exact path prefixes
`/auth`, `/patients`, `/entries`, `/doctors`, `/alerts`, `/admin`,
`/health` straight to the FastAPI backend (see "CORS: dev-server proxy"
below). A route named `/patients` or `/alerts` collides with that list —
client-side nav (`<NavLink>`/`useNavigate()`) never notices, but a full
page load/refresh/bookmark at that URL hits the proxy instead of the SPA
and shows raw backend JSON with no app UI. This was a real bug found
during this session's own verification — see [[decisions-log]]. **Any
future top-level route must avoid this proxy's path-prefix list**, not
just avoid colliding with an existing screen name.

### No baseline-band chart — same real backend-scope gap the Flutter build already found
`TrendChart.jsx` plots the patient's actual recorded values over time
rather than the prototype's shaded "learned normal" band, for the exact
same reason `mobile_app`'s `TrendChart` (a different file, same name) does
— see that section above and [[api-contracts]]. Confirmed still true this
session, not re-investigated from scratch.

### Patient name on the detail screen: looked up from roster/alerts, not `PatientOut`
`GET /patients/{id}` (`PatientOut`) has no field for the patient's own
name (see [[api-contracts]]) — only `assigned_doctor_name`/
`attendant_name`. `mobile_app` sidesteps this by passing the name in via a
Dart constructor argument from the roster tap; this build can't do the
same for a route reachable by direct URL (see the routing note above), so
`PatientDetailScreen.jsx` looks the name up from whichever of
`DoctorDataContext`'s already-loaded `roster`/`alerts` arrays has a
matching `patient_id` instead — both already carry the name. A real gap
found and fixed this session, not designed in from the start — see
[[decisions-log]].

## React web app (`web_app/`) — admin role, built 2026-08-29 (final session) — completes all three roles on both platforms

Mirrors `mobile_app/lib/screens/admin/`'s admin section (one screen:
People & roles — list, create, edit) against the same unmodified backend,
adapted to the prototype's actual desktop table layout rather than
mobile's stacked cards — same "a web app has the room a phone doesn't"
reasoning the patient- and doctor-role builds already used. Full build/
verification narrative in [[decisions-log]]; this is the structural/file
reference.

### New/changed files
```
web_app/
  src/
    services/
      adminService.js       # GET/POST /admin/users, PATCH
                             # /admin/users/{id} — mirrors
                             # mobile_app/lib/services/admin_service.dart
    state/
      AdminDataContext.jsx  # useAdminData() — mirrors
                             # mobile_app/lib/state/admin_data_provider.dart's
                             # shape exactly: one `users` list, loadAll()
                             # once per sign-in, createUser/updateUser
                             # update it in place rather than re-fetching
    components/
      AdminShell.jsx         # sidebar nav shell — a single "People &
                              # roles" item, matching the prototype's own
                              # single a-people screen (no other admin
                              # screens exist). Same sidebar shape as
                              # DoctorShell/PatientShell for visual
                              # consistency, even with only one destination.
    screens/admin/
      PeopleScreen.jsx        # GET /admin/users — searchable table
                              # (Person/Role/Linked to/Disease track),
                              # "Invite a person" button. Content/layout
                              # source: the prototype's a-people screen. No
                              # "Account" status column: `users` has no
                              # status column and none was added (see
                              # context/api-contracts.md). The prototype's
                              # decorative "Red-flag rule sets" card (no
                              # backing endpoint/data) is left out, same as
                              # mobile_app's admin build.
      UserFormScreen.jsx      # ONE form for both create (POST, all four
                              # roles) and edit (PATCH — name/role/
                              # phone_or_email/language_preference only, no
                              # password field, matching the backend's real
                              # supported fields exactly, with an explicit
                              # inline note instead of silently hiding the
                              # password field) — mirrors
                              # user_form_screen.dart's shared-screen
                              # pattern. Edit mode looks the existing user
                              # up from AdminDataContext's already-loaded
                              # `users` list (no GET /admin/users/{id}
                              # endpoint exists) — same "look it up from
                              # already-loaded data" pattern
                              # PatientDetailScreen.jsx uses for the
                              # missing-patient-name gap above.
    App.jsx                  # extended: session.role === 'admin' gets
                              # <AdminShell/> route tree (checked before
                              # the doctor/patient branches, above the
                              # generic PlaceholderScreen fallback); a
                              # third data-load effect, keyed on
                              # session.userId via useRef (same shape as
                              # the doctor effect, not a fire-once
                              # boolean), reloads /admin/users on every
                              # admin sign-in; adminData.reset() added to
                              # the sign-out cleanup effect
    main.jsx                 # wrapped in <AdminDataProvider>
```

### Routing: `/people`, `/people/new`, `/people/:userId/edit` — deliberately NOT `/admin`
Same collision this session's own doctor-role build hit and fixed for
`/patients`/`/alerts` (see the routing note above) — `vite.config.js`'s
dev-server proxy forwards `/admin` straight to the FastAPI backend, so an
admin route named `/admin` would break on a full page load/refresh.
Checked the proxy's path-prefix list *before* picking `/people`, avoiding
a repeat of that bug rather than rediscovering it — verified directly: a
full-page navigation to `/people`, `/people/new`, and an edit URL all load
the SPA correctly. **Any future top-level web-app route must keep doing
this check first.**

### No `GET /admin/users/{id}` — edit mode looks the user up from the already-loaded list
Same "no per-id fetch endpoint" shape as the patient-name gap above:
`UserFormScreen.jsx`'s edit mode finds the user by matching the
`:userId` route param against `AdminDataContext`'s already-loaded `users`
array rather than fetching it directly. This also means a direct URL/
refresh at `/people/:userId/edit` correctly waits for that list to finish
loading (the same `App.jsx` effect that loads it on every admin sign-in)
before deciding the id doesn't exist, rather than flashing a false
"not found" on first paint.

**This completes all three roles (patient/doctor/admin) on BOTH platforms**
— see [[progress]] for the project-wide feature-complete summary.

## React web app (`web_app/`) — direct messaging, added 2026-09-07 (final session)

`src/services/messageService.js` (GET/POST `/patients/{id}/messages`, mirrors
`mobile_app/lib/services/message_service.dart`) and `src/screens/MessagesScreen.jsx`
— the latter lives at the **top level** of `screens/` (not under `patient/` or
`doctor/`), same reasoning as the Flutter build's own top-level placement: the chat UI
doesn't differ by role, only `patientId`/`title`/an optional `backTo`+`backLabel` (for
the doctor's back-navigation) are passed in as props. Reached at `/messages` (a new
`PatientShell.jsx` sidebar item, title = the assigned doctor's name from
`usePatientData().profile`) for the patient role, and at
`/roster/:patientId/messages` (a new "Messages" button on `PatientDetailScreen.jsx`,
via a small wrapper `src/screens/doctor/PatientMessagesScreen.jsx` that resolves the
patient's name from `DoctorDataContext`'s already-loaded roster/alerts — same
"no per-id name field, look it up from already-loaded data" pattern
`PatientDetailScreen.jsx` itself already uses, see that section above) for the
doctor role. Checked `vite.config.js`'s dev-server proxy path list before picking both
route names, same discipline every prior route addition in this app has used — neither
`/messages` nor `/roster/:patientId/messages` collides with the proxied prefixes
(`/auth`, `/patients`, `/entries`, `/doctors`, `/alerts`, `/admin`, `/health`).

**Polling stops on navigation away for a structurally different reason than the
Flutter build**: React Router unmounts a route's element when the user navigates to a
different route (unlike Flutter's `IndexedStack` tabs, which keep every tab's widget
alive) — so `MessagesScreen`'s `useEffect` cleanup (`clearInterval`) genuinely fires
on navigation with no extra visibility bookkeeping needed, unlike the Flutter side
where reaching this screen via a *pushed* route rather than a persistent tab was a
deliberate choice made specifically to get the same guarantee (see the Flutter
section above and [[decisions-log]]).

Local `useState`/`useEffect` (a `setInterval` re-fetch every 12s, cleared on unmount),
not folded into `PatientDataContext`/`DoctorDataContext` — same "not needed anywhere
else, a dedicated context would add indirection with no reuse benefit" reasoning as
the Flutter build.

**One new lint warning, not a bug**: `npm run lint` (oxlint) flags a
`set-state-in-effect` info-level warning on `MessagesScreen.jsx`'s data-fetch effect —
a standard "fetch on mount" pattern (the effect calls the local `load()` async
function directly, and oxlint traces into its same-file body far enough to see the
`setState` calls before its first `await`). Harmless and not restructured — same
tolerated-warning category as this codebase's existing `only-export-components`
warnings on every Context file, never fixed either. See [[api-contracts]]'s
Verified section.

## Context logging
- Update `context/schema.md`, `context/api-contracts.md`, `context/decisions-log.md`,
  `context/progress.md` as work happens, not just at the end of a session — see the
  CLAUDE task instructions for what goes in each file.
