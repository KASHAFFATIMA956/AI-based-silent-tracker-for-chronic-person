# Pre-deployment checklist (Railway)

Consolidated from a full re-read of `decisions-log.md` (every entry, start to
finish) and `progress.md`, plus a fresh code-level search — not just the
items already top-of-mind. See [[decisions-log]] for the original reasoning
behind each shortcut where cited.

**Legend**: 🔴 MUST FIX (breaks or is insecure in production) · 🟡 SHOULD FIX
(works but risky/fragile) · 🟢 ACCEPTABLE AS-IS (explained why) · ✅ FIXED AND
VERIFIED (config written, then actually built/run/exercised — not just
written and assumed to work; see [[decisions-log]] for the verification
narrative).

## 🔴 MUST REVIEW BEFORE NON-DEMO USE — chest-pain first-aid guidance panel (2026-09-07)

**This item is categorically different from every other item in this file.** Every
other 🔴/🟡 item below is an infrastructure/security risk (a crashed server, a leaked
token, a wiped volume). This one is a **clinical-safety risk**: the Result screen now
shows fixed first-aid text — including active medication guidance (chewing aspirin) —
to a real patient or attendant on a Red chest-pain result. See [[decisions-log]] and
[[progress]] for the full build narrative; this entry exists specifically to flag what
"done" does and does not mean here.

**What was built** (`mobile_app/lib/core/first_aid_guidance.dart` +
`chest_pain_first_aid_panel.dart`, `web_app/src/core/firstAidGuidance.js` +
`ChestPainFirstAidPanel.jsx`): a fixed, hand-authored panel shown on a Red result with
"Chest pain" in `symptom_names` — a prominent "call emergency services immediately"
instruction, a 4-item contraindication checklist gating a secondary aspirin-chewing
instruction, a suppressed-state fallback when the checklist isn't fully confirmed, and
a "not personal medical advice" disclaimer. Content is paraphrased from two real AHA
public first-aid pages (cited in-app and in [[decisions-log]]), not AI-generated per
request, and does not touch `app/services/rules.py`'s scoring at all.

**What "real clinical review" would need to cover before this is more than a hackathon
demo feature** — none of the following has happened yet:
1. **A licensed clinician (cardiologist/emergency medicine) must review the exact
   wording** of both the primary and aspirin-specific instructions — this session's
   text is a good-faith paraphrase of AHA public materials by a coding assistant, not
   clinician-authored or clinician-approved copy, the same standard this project
   already holds `rules.py`'s numeric thresholds to (see item 12 below).
2. **The contraindication checklist's completeness must be clinically verified.** Only
   four contraindications are checked (allergy, blood thinners, bleeding disorder,
   pediatric). A real reviewer needs to confirm this is the right/complete list for a
   lay bystander context — e.g. whether other conditions (recent GI bleed, aspirin
   sensitivity/asthma triad, current NSAID use, pregnancy) should be added, and whether
   a lay checklist is even the right mechanism vs. always deferring to an emergency
   dispatcher's own judgment.
3. **Dosage/form guidance ("162-325mg, non-enteric-coated") needs verification against
   current clinical guidelines**, not just this session's one-time web search — clinical
   guidance can change, and a single AI-driven search is not equivalent to checking
   current authoritative sources at the time of deployment.
4. **Localization/regional-practice review**: this app is Pakistan-context (seeded
   `emergency_contact_phone: "1122"`), but the guidance text says "call your local
   emergency number" generically — a reviewer should confirm this is appropriate for
   the actual deployment region(s) rather than assuming US-centric AHA guidance
   transfers directly.
5. **Legal/liability review** — a hackathon prototype giving medication guidance is a
   fundamentally different liability posture than passive risk-level display; this
   needs sign-off from whoever owns that risk for this project, not just a code review.
6. **A UX/accessibility review of the checklist mechanism itself** — confirm the
   "unchecked = suppressed" default is legible under real emergency-stress conditions
   (small font, low light, a panicking attendant), not just correct in code.

**Until all of the above happens, this panel must be presented as a hackathon/demo
feature only** — do not deploy it, describe it, or demo it to real clinicians/patients
as production-ready medical guidance. If this project is ever used with real patients,
this panel should be treated as a hard blocker, not a "should fix."

---

## ✅ Fixed and verified (2026-08-29, deployment-readiness pass, part 1: Tier 1)

The four items that would have blocked a deploy attempt from running at all
(as opposed to running insecurely or incompletely) — items 3, 4, 6, and 11
below. Each was verified with a real `docker build` + `docker run`, not just
written and assumed correct — see [[decisions-log]] for the full narrative
(fresh empty Postgres to prove migrations run from zero, a deliberately
legacy `postgres://` URL to exercise the normalization, a non-default
injected `$PORT`, a direct curl hit at nested SPA routes, etc.).

## ✅ Fixed and verified (2026-08-29, deployment-readiness pass, part 2: Tier 2)

The three items that would have let a deploy run but insecurely/pointed at
the wrong backend — items 1, 2, and 5 below. Also verified for real, not
just written: a real `Settings()` construction that actually crashed the
way it's supposed to when the JWT-secret safeguard should trigger; a real
running backend hit with real cross-origin `curl` preflight/actual
requests from disallowed AND allowed origins; and — the most convincing
check — a real Chrome browser running `web_app`'s dev server configured to
call the backend directly cross-origin (bypassing the Vite proxy
entirely), completing a real login, a real cross-origin `GET`, and a real
cross-origin `POST` (mark-alert-reviewed, confirmed persisted via a direct
Postgres `SELECT`), with zero console errors. See [[decisions-log]] for
the full narrative.

Item 7 (local-disk audio storage) and every Tier 3 item (`flutter test`,
seed/migration process decisions, stray test-account cleanup, unreviewed
clinical thresholds, refresh tokens) remain explicitly **not** touched —
deliberately deferred to a later session, per the task's own scope.

## ✅ Fixed and verified (2026-08-29, deployment-readiness pass, part 3: final deploy prep)

Item 7 (local-disk audio storage — fixed via a Railway Volume, deliberately
not cloud/S3 storage; see that item's own entry for the full reasoning and
verification, including a real Docker-Volume destroy-and-recreate proof).
Also produced the **Railway deploy runbook** immediately below — the exact
env-var list and ordering, the frontend rebuild commands, and the one-time
`seed.py` command — everything needed to actually run the deploy, not just
the individual fixes. Every Tier-3 item still open (8–10, 12–13) remains
untouched.

---

## Railway deploy runbook

Everything below is the exact sequence to actually deploy this project —
pulling together every fix above into one ordered checklist. Nothing here
has been run against a real Railway project (no live account/credentials
exist in this environment); each individual piece was verified locally
(Docker builds/runs, real containers, real API calls — see each numbered
item above) to the same standard as everything else in this file.

### Step 1 — Backend service

1. Create the Railway project, add a **Postgres** database to it (Railway
   provisions this as its own service/plugin).
2. Create the **backend** service from this repo, with **Root Directory**
   set to `Backend` (this is a monorepo — three deployable pieces live in
   one repo: `Backend/`, `web_app/`, and `mobile_app/`, which isn't
   deployed to Railway at all — see item 6's Flutter-web note). Railway
   auto-detects `Backend/Dockerfile` (via `Backend/railway.json`'s
   `builder: DOCKERFILE`) — no build command needed.
3. Link the Postgres database to the backend service so `DATABASE_URL` is
   auto-injected (Railway usually suggests this automatically when you add
   a database to a project with an existing service; if it doesn't, add a
   `DATABASE_URL` variable on the backend service that references the
   Postgres service's own `DATABASE_URL`). No manual value needed — and no
   need to worry about which scheme Railway hands back (`postgres://` vs
   `postgresql://`) — `app/core/config.py`'s normalizer (item 11) handles
   either.
4. Attach a **Volume** to the backend service (Service → Settings →
   Volumes → New Volume) — mount it at `/data`.
5. Set these variables on the **backend** service (order within this step
   doesn't matter — none of these five depend on anything not already
   known at this point):
   - `JWT_SECRET_KEY` — a real secret, e.g. generate with `openssl rand
     -hex 32`. **Set this one — the app will refuse to boot without it**
     once `ENVIRONMENT` below is set (item 1's safeguard).
   - `ENVIRONMENT` = `production`
   - `AUDIO_STORAGE_PATH` = `/data/audio_storage` (matching the Volume's
     mount path from step 4 — item 7)
   - `ANTHROPIC_API_KEY` — optional; leave unset to run rule-engine-only
     (fully functional, `source` stays `"rule"`), or set a real key for
     the AI-merged demo path (`source: "merged"`, transcript-based symptom
     extraction).
   - `CORS_ALLOWED_ORIGINS` — **leave unset for now** (it'll default to
     the local-dev origins, which is fine — nothing external can call this
     API successfully yet anyway until the frontend exists). Come back to
     this in Step 3.
6. Deploy. Check the deploy logs for `Running database migrations...`
   followed by the `Running upgrade` lines (first deploy only — a redeploy
   later correctly shows no `Running upgrade` line, just the no-op case
   already verified) and then `Uvicorn running on http://0.0.0.0:$PORT`.
   Hit `<backend-url>/health` — should return
   `{"status":"ok","environment":"production"}`. If `environment` shows
   `"development"` instead, `ENVIRONMENT` wasn't actually set — fix that
   before continuing.
7. **Note the backend's assigned Railway URL** — you'll need it for both
   remaining steps below.

### Step 2 — Web frontend (`web_app`)

1. Create a second Railway service from the same repo, **Root Directory**
   set to `web_app`. Railway auto-detects `web_app/Dockerfile`.
2. Set `VITE_API_BASE_URL` on this service to the backend's real URL from
   Step 1.7 (no trailing slash), e.g.
   `https://<your-backend-service>.up.railway.app` — Railway auto-forwards
   this as a build arg (the Dockerfile declares a matching `ARG`, see item
   5) on every build/rebuild.
3. Deploy. **Note this service's own assigned Railway URL too.**

### Step 3 — Close the loop: CORS

1. Go back to the **backend** service's variables and set
   `CORS_ALLOWED_ORIGINS` to the `web_app` URL from Step 2.3 (comma-separate
   a second value if you ever add a custom domain). Railway restarts the
   service on a variable change, which is what's needed here — no manual
   redeploy trigger required.
2. Verify: open the `web_app` URL in a real browser, log in as a seeded
   patient/doctor/admin account, confirm no CORS errors in the console and
   that real data loads — this is exactly the check this session's item 2
   verification already proved works mechanically; this step is just
   confirming it against the real deployed URLs instead of the local
   simulation.

### Step 4 — Seed data (run exactly once)

`seed.py` **clears existing rows before inserting** — safe to re-run
against a throwaway local DB (every session in this project has done
this), but running it more than once against the real deployed DB **wipes
and resets all demo state**, including anything created live during a
demo (item 9). Run it exactly once, right after Step 1's first successful
deploy, before any real interaction happens against the deployed database.

Two ways to run it against the real Railway Postgres, depending on what
you have set up locally:

- **With the Railway CLI** (if installed and linked to the project —
  `railway login`, `railway link`): from `Backend/`,
  `railway run --service <your-backend-service-name> -- python seed.py`
  — this runs `seed.py` on your machine with the linked service's real
  environment variables (including the real `DATABASE_URL`) injected.
- **Without the CLI**: get the Postgres service's *public/external*
  connection string from Railway's dashboard (the Postgres service's own
  "Connect" panel — distinct from the internal `DATABASE_URL` other
  Railway services use to reach it privately), then run locally from
  `Backend/`:
  `DATABASE_URL="<public-connection-string-from-Railway>" .venv/bin/python seed.py`
  (or `python3 seed.py` if not using the project's own `.venv`).

Either way, confirm success the same way every prior seeding pass in this
project has: the script prints a per-table row-count summary and the demo
login line (`password = 'RozNoor@123'`) — then do one real login against
the deployed URL to confirm it actually works, not just that the script
exited cleanly.

### Step 5 — Rebuild the Flutter app (once you have a real backend URL)

Not part of the Railway project itself (Flutter isn't deployed to
Railway — see item 6), but needs the same real backend URL from Step 1.7.
From `mobile_app/`:
```
flutter build apk --release --dart-define=ROZNOOR_API_BASE_URL=https://<your-backend-service>.up.railway.app
```
Then reinstall the resulting APK on any test device — this is baked in at
build time, not runtime-configurable (see [[pending-device-tests]]). See
item 5 for the full verification narrative of this exact mechanism.

---

## 🔴 MUST FIX before deployment — ALL SEVEN ITEMS NOW ✅ FIXED (2026-08-29)

Kept under its original heading (rather than moved/renamed) so the
original severity assessment stays visible — every item below was a real
🔴 when first written, not overstated. Item 11 (`DATABASE_URL` scheme),
listed separately under 🟡 further down since it was originally assessed
as lower-severity, is also fixed — see that item's own entry.

### 1. ✅ `JWT_SECRET_KEY` — FIXED AND VERIFIED (2026-08-29): reading from env was already correct; the "silently used in production" gap is now a hard startup failure instead
**Original state**: `Backend/app/core/config.py` read `jwt_secret_key` from
env var `JWT_SECRET_KEY` if set (pydantic-settings does this automatically
— confirmed already correct, no bug there), falling back to the literal
string `"insecure-dev-only-secret-change-me"` otherwise. The gap wasn't
*how* it reads the env var — it's that nothing stopped the insecure
default from being silently, successfully used in a real deployed
environment if the env var was simply forgotten. `.env` itself is
gitignored and was never committed at any point in git history (re-checked
this session, still empty) — the secret has never leaked, this was about
the *default's* reachability, not a leak.
**Fixed**: `Backend/app/core/config.py` — a `model_validator(mode="after")`
(`forbid_insecure_secret_outside_dev`) that raises `ValueError` at
`Settings()`-construction time — i.e. the app cannot finish booting at all
— if `environment` (env var `ENVIRONMENT`, already an existing field) is
anything other than `"development"` AND `jwt_secret_key` is still the
literal insecure default. Local dev is completely unaffected:
`ENVIRONMENT` defaults to `"development"`, so the validator is a no-op
there exactly as before. **You will need to set two env vars on Railway,
not just one**: `ENVIRONMENT=production` (to arm the safeguard —
`GET /health` already echoes this back, useful for confirming a deployed
instance is in the mode you think it's in) and a real
`JWT_SECRET_KEY` (e.g. `openssl rand -hex 32`) — this session did not set
or need to know the actual secret value, exactly as asked; only the code
was changed. `Backend/.env.example` updated to document both.
**Verified for real** — constructed `Settings()` for real (not mocked) in
four scenarios, each as its own real Python process: (a) no
`ENVIRONMENT`/no `JWT_SECRET_KEY` set → boots fine with the insecure
default, confirming zero regression to local dev; (b) `ENVIRONMENT=production`,
no `JWT_SECRET_KEY` → the import of `app.core.config` itself raises
`ValidationError` with the exact intended message — this is the module-level
`settings = Settings()` failing, meaning the real app process would crash
at startup, not just an isolated unit check; (c) `ENVIRONMENT=production`
+ a real `JWT_SECRET_KEY` value → boots fine; (d) the existing local
`Backend/.env` (`postgresql+psycopg2://...`, no `ENVIRONMENT` line) still
resolves completely unchanged, confirming no regression to the setup every
prior session in this project has used.

### 2. ✅ CORS — FIXED AND VERIFIED (2026-08-29): real `CORSMiddleware`, specific allowed origins via env var, no wildcard
**Original state**: `Backend/app/main.py` had zero CORS configuration.
Every session that built `web_app/` explicitly flagged this as dev-only
(`vite.config.js`'s `server.proxy`) and called out the production gap each
time without fixing it — flagged and deferred across four separate
sessions before this one. `vite.config.js`'s proxy only exists inside
`vite dev`'s own process; `npm run build`'s static output has no server
behind it to route around the browser's same-origin policy.
**Fixed**: `Backend/app/main.py` — real `fastapi.middleware.cors.
CORSMiddleware`, added right after `app = FastAPI(...)` so it wraps every
route. `Backend/app/core/config.py` — a new `cors_allowed_origins` field
(env var `CORS_ALLOWED_ORIGINS`, comma-separated EXACT origins, deliberately
never `"*"` per your explicit instruction) with a `cors_allowed_origins_list`
property that splits/strips it, defaulting to Vite's own dev port on both
`localhost`/`127.0.0.1` so local dev keeps working unchanged.
`allow_credentials=False` — this app's auth is a Bearer token in an
`Authorization` header (`web_app/src/core/tokenStorage.js` uses
`localStorage`, never a cookie), which CORS doesn't treat as a
"credential" the way cookies are, so there's no cookie-based session
anywhere for `allow_credentials` to matter to. `allow_methods`/
`allow_headers` stay `["*"]` — your "be specific" instruction was about
origins specifically (the actual security boundary here — an arbitrary
site being allowed to call this API on a signed-in user's behalf), not
about which HTTP methods/header names a genuinely allowed origin can use.
`Backend/.env.example` updated with the new var.
**You will need to set** `CORS_ALLOWED_ORIGINS` on Railway to the real
deployed `web_app` origin once known, e.g.
`https://roznoor-web-production.up.railway.app` (comma-separate a second
value if there's ever a custom domain too).
**Verified for real, at two levels**: (1) direct `curl` against a real
running instance of the updated backend, with real `Origin` headers — a
preflight `OPTIONS` for a `PATCH` (the admin edit-user shape) from the
allowed origin returned the full real CORS header set
(`access-control-allow-origin: http://localhost:5173`,
`access-control-allow-methods`, etc.); a real `GET /health` from that same
origin echoed `access-control-allow-origin` back; the identical request
from a disallowed origin (`http://evil-example.com`) got a real `200` from
the server (correct — CORS is enforced by the browser reading response
headers, not the server refusing the request) but **no**
`Access-Control-Allow-Origin` header at all, which is what actually makes
a browser block it; setting `CORS_ALLOWED_ORIGINS` to a custom value
(simulating the real deployed origin) correctly allowed that origin AND
correctly stopped allowing the previous default — proving the env var
genuinely drives this, not a hardcoded fallback list. (2) **The
convincing end-to-end check**: ran `web_app`'s real Vite dev server with
`VITE_API_BASE_URL=http://localhost:8000` (forcing every fetch to hit the
backend directly, cross-origin, bypassing the dev-proxy entirely — a
genuine different-origin scenario for the browser, not a simulation),
opened it in an actual Chrome browser (`claude-in-chrome`), and
deliberately logged out first so the session was genuinely fresh (not
reusing an already-authenticated `localStorage` token from an earlier
test) — this matters because `POST /auth/login` is the one call in this
app that carries no `Authorization` header at all, a genuinely different
CORS case from every other request: a real cross-origin `POST
/auth/login` (confirmed `200` via `read_network_requests`) logged in for
real, followed by real cross-origin `GET /auth/me`, `GET /patients/2`,
`GET /patients/2/symptom-checklist`, `GET /entries/2/timeline` all loading
the real Home screen. Separately, a doctor-role session exercised a real
cross-origin `POST /alerts/{id}/review` (clicking "Mark reviewed"),
confirmed **persisted via a direct Postgres `SELECT`** (`reviewed`
flipped to `true` for that row), not just a UI state change. Zero console
errors/CORS warnings at any point across either session (checked via
`read_console_messages`). Both dev processes (`vite`, `uvicorn`) were
restored to their normal
non-cross-origin-forced configuration afterward.

### 3. ✅ No Railway deployment configuration exists at all — FIXED AND VERIFIED (2026-08-29)
**Original state**: `find . -iname "railway*" -o -iname "Dockerfile*" -o
-iname "nixpacks*" -o -iname "Procfile"` returned nothing in the whole repo.
Neither `decisions-log.md` nor `progress.md` mentioned this — every prior
pass verified against a local `uvicorn`/Docker-Postgres dev setup and never
touched deployment config.
**Fixed**: `Backend/Dockerfile` (python:3.12-slim, installs `ffmpeg` — see
item 4 — then app deps), `Backend/start.sh` (container entrypoint: runs
`alembic upgrade head`, then `exec uvicorn app.main:app --host 0.0.0.0
--port "${PORT:-8000}"` — real `$PORT` binding, not hardcoded), `Backend/
railway.json` (`builder: DOCKERFILE`, `healthcheckPath: /health`), and
`Backend/.dockerignore` (keeps `.venv`/`.env`/`audio_storage`/etc. out of
the image).
**Verified for real** — built the actual image (`docker build`, succeeded,
~75s) and ran it as a real container: a brand-new, genuinely empty Postgres
16 container (confirmed `\dt` showed zero tables beforehand) went from 0
tables to all 11 (+`alembic_version`) purely from the container's own
startup script, with `PORT=5599` (a non-default value, chosen specifically
to prove it isn't just falling back to 8000 — confirmed `docker port` shows
only `5599`, and the process inside the container is literally `uvicorn ...
--port 5599`) mapped and reachable, `GET /health` returning `200`. Restarted
the same container afterward (simulating a redeploy) — the second migration
run correctly logged as a no-op (no `Running upgrade` lines, since already
at head) rather than erroring, and previously-seeded data survived. See
item 11 below for the `$DATABASE_URL` scheme detail and item 4 for the
`ffmpeg` verification — both exercised in this same container run, not
separately.

### 4. ✅ `ffmpeg` system binary — FIXED AND VERIFIED (2026-08-29)
**Original state**: `app/services/audio_analysis.py` decodes every
uploaded voice recording via a `ffmpeg` subprocess (`shutil.which("ffmpeg")`
check at `audio_analysis.py:182`, soft-fails to `None`/no-crash if missing —
confirmed by reading the actual guard code, not just the doc comment).
`requirements.txt`'s own comment already stated plainly: "that binary must
be present on PATH wherever this backend runs (already present on the dev
machine used to build/verify this)" — i.e. this had only ever been true by
accident of the dev machine's existing OS packages, never deliberately
provisioned. **Impact if missed**: not a crash (the soft-fail contract
holds), but the entire acoustic-analysis feature (`POST /entries/{id}/
audio`) silently does nothing useful — `has_audio` flips `true` but
`acoustic_features` stays `null` forever.
**Fixed**: `Backend/Dockerfile`'s first layer —
`apt-get install -y --no-install-recommends ffmpeg` — before any Python
dependency is installed.
**Verified for real, inside the actual running container from item 3**
(not a separate throwaway check): `docker exec ... which ffmpeg` →
`/usr/bin/ffmpeg`; `docker exec ... ffmpeg -version` → real version output
(`ffmpeg version 7.1.5-...`); and — the check that actually matters, since
it's what the app code itself does, not just a shell PATH check —
`docker exec ... python3 -c "import shutil; print(shutil.which('ffmpeg'))"`
→ `/usr/bin/ffmpeg`, confirming `audio_analysis.py`'s own guard sees it.

### 5. ✅ Frontend API base URLs — FIXED AND VERIFIED (2026-08-29): both build-time mechanisms confirmed to actually work; exact commands below, no real URLs guessed
**Original state**: `web_app/src/core/appConfig.js` — `API_BASE_URL`
defaults to `''` (relative-path, correct for the Vite dev proxy) unless
`VITE_API_BASE_URL` is set at build time. `mobile_app/lib/core/
app_config.dart` — `apiBaseUrl` defaults to `'http://localhost:8000'`
unless built with `--dart-define=ROZNOOR_API_BASE_URL=...`, baked in at
build time, not runtime-configurable. Both mechanisms already existed in
code — nothing here was broken — but neither had actually been *proven*
to work end-to-end through a real build, and `web_app/Dockerfile` (written
in the Tier-1 pass) didn't yet have the plumbing to let a Railway build
actually pass `VITE_API_BASE_URL` through to `npm run build` at all (a
`docker run -e` would never reach a build step — only `docker build
--build-arg` does).
**Fixed**: `web_app/Dockerfile` — added `ARG VITE_API_BASE_URL=""` +
`ENV VITE_API_BASE_URL=$VITE_API_BASE_URL` right before `RUN npm run
build`, so the value genuinely flows from a build arg into Vite's own
`import.meta.env` static replacement. Railway's Dockerfile builder
auto-forwards any service variable whose name matches a declared `ARG` as
a build arg — no separate "build args" UI/config needed beyond setting the
variable on the service. No code changes were needed for
`mobile_app` — its mechanism was already correct, just unverified.
**Verified for real, both mechanisms, per your explicit "don't guess the
real URLs, just prove the plumbing works" instruction** (a fake but
realistic-shaped URL was used purely to prove the pipe carries the value
through correctly, never to guess or hardcode a real endpoint): (1)
`docker build --build-arg VITE_API_BASE_URL="https://roznoor-backend-production.up.railway.app"`
— extracted the actual built image's `dist/assets/*.js` and grepped it:
the literal URL string is really inlined into the minified bundle
(`Jn=\`https://roznoor-backend-production.up.railway.app\``), not just
present in a config file that never gets read. A build with the arg left
unset confirmed the negative case too — zero occurrences of any backend
URL in the bundle, correctly falling back to the relative-path default,
no regression. (2) `flutter test --dart-define=ROZNOOR_API_BASE_URL=
https://roznoor-backend-production.up.railway.app` against a throwaway
verification test (not the committed `widget_test.dart` — that file is
Tier-3 scope, untouched) that imports `AppConfig` directly: confirmed
`AppConfig.apiBaseUrl` resolved to exactly that URL; the same test without
the dart-define confirmed it falls back to `http://localhost:8000`
unchanged. Throwaway test file deleted after use — nothing new left in
`mobile_app/test/`.

**Exact commands to run once you have the real Railway URLs** (nothing
below has been run against a real deployment — these are the commands
this session's verification confirms will actually work):
- **`web_app`, via Railway**: set a `VITE_API_BASE_URL` variable on the
  `web_app` Railway service to the backend's real deployed URL (no
  trailing slash), e.g. `https://<your-backend-service>.up.railway.app` —
  Railway auto-forwards it as a build arg on the next deploy/redeploy, no
  other action needed.
- **`web_app`, building locally instead** (e.g. to sanity-check before
  pushing): `docker build --build-arg VITE_API_BASE_URL=https://<your-backend-service>.up.railway.app -t roznoor-web .`
  from `web_app/`.
- **`mobile_app`, rebuilding the distributed APK**: from `mobile_app/`,
  `flutter build apk --release --dart-define=ROZNOOR_API_BASE_URL=https://<your-backend-service>.up.railway.app`
  — then reinstall on any test device; this is baked in at build time, not
  runtime-configurable (see [[pending-device-tests]]). A real `https://`
  URL here also incidentally satisfies Android's cleartext-traffic block
  on release builds for free (the debug-only `network_security_config.xml`
  opt-in stays correctly scoped to `src/debug/` and needs no change).

### 6. ✅ React Router client-side routes need a static-host SPA fallback — FIXED AND VERIFIED (2026-08-29)
**Original state**: `web_app`'s routes (`/home`, `/roster/:id`,
`/people/:userId/edit`, etc.) are all client-side-only (React Router). Two
separate sessions already found and fixed the *dev-server* version of this
exact bug class (a route colliding with `vite.config.js`'s proxy path list,
breaking on full-page reload/direct URL — see [[decisions-log]], the doctor-
and admin-role passes). The *production* version of the same underlying
risk had never been addressed: a static file host returns a real 404 for a
direct URL/refresh at any client-side route unless explicitly configured to
fall back to `index.html` for unmatched paths.
**Fixed**: `web_app/Dockerfile` (multi-stage: `node:20-alpine` builds the
Vite bundle, then `nginx:1.29-alpine` serves it — no Node toolchain in the
final image), `web_app/nginx.default.conf.template` (`try_files $uri $uri/
/index.html` for everything under `/`, but a real `404` — not the
fallback — for a genuinely missing file under `/assets/`, so a broken build
reference still fails loudly rather than silently serving HTML), and
`web_app/railway.json`/`.dockerignore`. Uses the official nginx image's
built-in template-substitution entrypoint (`/etc/nginx/templates/*.template`
→ `envsubst` on container start) for `${PORT}` — no custom entrypoint script
needed, same `$PORT`-at-runtime requirement as the backend.
**Verified for real** — built the actual image (`docker build`, succeeded)
and ran it with a non-default injected `PORT=6688`: confirmed the generated
`/etc/nginx/conf.d/default.conf` inside the running container really had
`listen 6688;` (not a literal unsubstituted `${PORT}`). Then, exactly
reproducing how the two prior dev-proxy bugs were originally caught — a
**direct curl hit** at each nested route, not client-side navigation:
`GET /roster/2`, `/people/new`, `/people/19/edit`, `/timeline` all returned
`200` with the real SPA shell (`<title>RozNoor</title>`, the real built JS
bundle's `<script src>`) rather than a 404; a genuinely unknown path
(`/totally-bogus-nonexistent-path`) also correctly fell back to the shell,
matching React Router's own client-side catch-all; a real static asset
(`/assets/index-*.js`) still resolved `200` (not swallowed by the
fallback); and a deliberately-nonexistent asset path correctly still `404`s.

**Flutter web/static — checked, not applicable.** `mobile_app/web/` exists
but is unused default `flutter create` scaffold cruft — grepped the entire
[[decisions-log]] history and found zero mentions of `flutter build web` or
any Flutter-web deploy intent anywhere across every session; every Flutter
verification pass built `linux --debug` (desktop, for Xvfb testing) or a
real Android APK, never web. `mobile_app` is not part of this project's web
deployment surface — `web_app/` (React) is the only web frontend. Nothing
built or needed here.

### 7. ✅ Local-disk audio storage — FIXED AND VERIFIED (2026-08-29): a Railway Volume, deliberately not cloud/S3 storage
**Original state**: `app/core/config.py` — `audio_storage_dir: str =
"audio_storage"`, a plain relative filesystem path with no way to point it
anywhere else. Flagged repeatedly and consistently in [[decisions-log]] as
"a HACKATHON-SCOPE SHORTCUT... not multi-instance safe... would need a
real storage migration before any real deployment" since 2026-08-25.
Railway containers have an ephemeral filesystem by default — every
redeploy wipes anything written to local disk since the container last
started; a previously-uploaded Voice Diary recording would silently
vanish (the DB row would still say `has_audio: true`, but the file — and
any future re-analysis — would be gone).
**Why a Volume, not cloud/S3 storage (explicit scope decision, not a
default)**: cloud object storage is the textbook production answer, but
it's the wrong-sized fix for this project right now — it would mean
provisioning an external account (AWS/Cloudflare/Backblaze, none of which
Railway offers natively), adding a new SDK dependency, real IAM/credential
management, and a genuine code rewrite of the upload/read path in
`app/routers/entries.py` — a lot of new surface area for a hackathon-scale
single-instance deployment that was never asked for. A **Railway
Volume** — a persistent disk Railway attaches directly to one service,
surviving restarts/redeploys — solves the actual problem (files vanishing
on redeploy) with zero new dependencies and a one-line code change
(`os.path.join`/`os.makedirs` already work identically against a relative
dev path or an absolute mount path — no rewrite needed). The real
trade-off, flagged plainly: a Volume attaches to exactly one service, so
this remains a single-backend-instance design (same limitation the
local-disk approach always had) — fine at this project's actual scale,
but genuinely not what you'd reach for if this needed to run more than one
backend replica. That's the real reason cloud storage would eventually be
the right call for a multi-instance deployment — just not the problem
being solved here.
**Fixed**: `Backend/app/core/config.py` — the field renamed
`audio_storage_dir` → `audio_storage_path`, now reading from env var
`AUDIO_STORAGE_PATH` (pydantic-settings' standard field→env-var mapping),
defaulting to the exact same relative `"audio_storage"` as before — zero
behavior change for local dev. `app/routers/entries.py` and
`app/models/entry.py`'s doc comment updated to match the rename.
`Backend/.env.example` documents the new var and the recommended
production value shape (`AUDIO_STORAGE_PATH=/data/audio_storage`, paired
with a Volume mounted at `/data`).
**You will need to, on Railway** (see the deploy runbook below for exact
ordering): attach a Volume to the backend service (Service → Settings →
Volumes → New Volume), mount it at `/data`, then set
`AUDIO_STORAGE_PATH=/data/audio_storage` as a service variable.
**Verified for real, including the actual property being fixed (not just
"the path is configurable")**: (1) unit-level — confirmed `Settings()`
falls back to the unchanged relative default with no env var set, and
correctly picks up an absolute env-var value, with zero regression to the
existing local `.env` setup. (2) Full functional round trip against the
real local dev backend with `AUDIO_STORAGE_PATH` pointed at a fresh
directory: submitted a real voice entry, uploaded a real synthetic WAV via
`POST /entries/{id}/audio`, confirmed `acoustic_features` came back
correctly populated (real `ffmpeg` decode + signal-processing pipeline,
unaffected by the path change) and the file landed at the new path, not
the old default — confirmed via the DB's own `audio_file_path` column and
a direct filesystem check. (3) **The actual "survives a redeploy" proof,
with a real Docker Volume mounted, run twice for contrast**: built the
real `Backend/Dockerfile` image, ran a container with a real Docker
named volume mounted at `/data` and `AUDIO_STORAGE_PATH=/data/
audio_storage`, uploaded a real recording, then **destroyed that
container entirely** (`docker rm -f` — exactly what a Railway redeploy
does to the old container) and started a **brand-new** container sharing
the same volume: the uploaded file was still there, and a real API call
against the new container still correctly returned `has_audio: true` +
real `acoustic_features` for that entry. Then, as an explicit negative
control: repeated the identical destroy-and-recreate cycle with the exact
same `AUDIO_STORAGE_PATH` env var but **no volume mounted** — the file
(and the directory itself) was completely gone in the new container,
concretely confirming Railway's ephemeral-filesystem behavior is real and
that the Volume specifically is what fixes it, not just "pointing at a
different path."

---

## 🟡 SHOULD FIX (works but risky/fragile)

### 8. `flutter test` failure — now actually root-caused, not just "confirmed pre-existing"
**What every prior session said**: flagged as failing, confirmed via
`git stash` to fail identically before any given session's changes, "not
investigated further."
**Actually diagnosed this session** — ran it and read the real exception,
not just the pass/fail line:
```
ProviderNotFoundException: Could not find the correct Provider<LanguageProvider>
above this BilingualText Widget
```
Root cause: `mobile_app/test/widget_test.dart` wraps `LoginScreen` in only a
single `ChangeNotifierProvider<AuthProvider>` (its own comment even
explains why — avoiding the full `RootRouter` flow's platform-channel
dependency on `flutter_secure_storage`). But `LoginScreen` itself now
renders `BilingualText`, which reads `LanguageProvider` via
`context.watch<LanguageProvider>()` — a provider the test never supplies.
Confirmed this is a **pure test-harness gap, not a real app bug**: the real
`mobile_app/lib/main.dart:22-29` wraps a full `MultiProvider` including
`LanguageProvider` correctly — the failure cannot happen in the shipped app,
only in this one under-provisioned test.
**Fix**: add `ChangeNotifierProvider(create: (_) => LanguageProvider())` to
the test's provider tree in `widget_test.dart`. Small, safe, isolated to the
test file — does not touch any shipped code path. Not deployment-blocking
(CI hygiene only), but "the one committed test is red on `main`" is worth
closing out rather than leaving permanently ignored, especially before
telling anyone this project is "feature-complete."

### 9. ✅ Migrate/seed deploy runbook — DOCUMENTED (2026-08-29): the migration half was already resolved, the seed half now has an exact, verified command
Every session ran `alembic upgrade head` and `python seed.py` by hand
against a throwaway local Postgres. **The migration half was already
resolved as of item 3** — `start.sh` runs `alembic upgrade head`
automatically on every container start, verified idempotent on a restart.
**The seeding half remains, correctly, a manual one-time step** — nothing
runs `seed.py` automatically (correctly — auto-seeding a production start
script would silently wipe/reset a real deploy on every restart, since
`seed.py` clears before inserting) — but it's no longer *undocumented*:
the "Railway deploy runbook" section above now gives the exact command
(two variants, with/without the Railway CLI), verified for real against
the project's own dev Postgres this session, plus the same repeated
warning about running it exactly once. Still your call whether the demo
deploy seeds the same fictional Ghulam Rasool/Zubaida Bibi/etc. roster
judges will see — that product decision itself wasn't made for you, only
the mechanics of doing it safely once you decide.

### 10. Accumulated stray test-account data in whichever Postgres becomes "the" demo database
[[decisions-log]] repeatedly and explicitly flags this across the doctor-,
Flutter-admin-, and web-admin-role passes: real test users
(`test.*.curl@example.com`, `ui.test.new*@...`, `web.test.new*@...`, several
renamed mid-test to `...EDITED`) were created via curl/UI verification and
never cleaned up, because **no `DELETE /admin/users/{id}` endpoint exists**.
If deployment reuses the same local dev Postgres data (via a dump/restore)
rather than a fresh Railway Postgres + a single clean `seed.py` run, this
clutter ships to the demo. **Fix**: deploy against a fresh Railway Postgres
instance and run `seed.py` once, rather than migrating the accumulated dev
database — sidesteps the missing-DELETE-endpoint gap entirely rather than
needing to build one under time pressure.

### 11. ✅ `DATABASE_URL` scheme compatibility — FIXED AND VERIFIED (2026-08-29), and the original "probably fine" assessment was WRONG for one real case
**Original state**: `Backend/app/core/config.py:19` expected (and its own
docstring/`.env.example` documented) the `postgresql+psycopg2://` scheme.
The original write-up guessed Railway injects bare `postgresql://` and
reasoned that'd be fine since SQLAlchemy defaults to the installed
`psycopg2` driver — true, but incomplete: it never actually tested the
**other** real-world scheme, the legacy `postgres://` (no `ql`), which
several platforms (Heroku historically, and some Railway templates/older
plugin versions) still use.
**Tested empirically before writing any fix** (`Backend/.venv/bin/python3`,
`sqlalchemy.create_engine()` against all three shapes directly): confirmed
`postgresql://...` and `postgresql+psycopg2://...` both work as guessed,
but `postgres://...` **hard-fails** —
`NoSuchModuleError: Can't load plugin: sqlalchemy.dialects:postgres`. This
would have meant a real, silent risk: if Railway (or whichever Postgres
plugin/version ends up provisioned) ever hands back the legacy scheme, the
app would crash at `Settings()`-construction time, before even reaching
`/health`.
**Fixed**: `Backend/app/core/config.py` — a `field_validator` on
`database_url` that rewrites `postgres://` → `postgresql://` →
`postgresql+psycopg2://` (a URL that already names a driver, e.g. the
existing `+psycopg2` default, passes through unchanged). Alembic's own
`env.py` reads `settings.database_url` too, so migrations get the same
normalization automatically — one fix, not two.
**Verified for real**: (1) unit-level — set `DATABASE_URL` to each of the
three shapes as a real env var and constructed `Settings()` for real each
time, confirming the normalized output and confirming the local dev
`.env` (`postgresql+psycopg2://...`) still resolves unchanged (no
regression); (2) full end-to-end — the same containerized deploy test from
item 3 was run with `DATABASE_URL="postgres://..."` (the scheme that
previously would have crashed) pointed at a brand-new empty Postgres, and
migrations ran and the app served real traffic successfully — proof this
isn't just a unit test in isolation, the actual failure mode is closed.

### 12. Rule engine / baseline / acoustic-signal thresholds — every non-doc-sourced number is an unreviewed Claude Code proposal
Already tracked in `progress.md`'s own "Open items needing your input"
section and re-confirmed present in the actual source this session
(`grep`'d `app/services/rules.py` and `app/services/audio_analysis.py` —
`NEEDS CLINICIAN REVIEW`/`NEEDS REVIEW`/`UNVALIDATED guess` comments at
`rules.py:103,116,143,148,161,170` and `audio_analysis.py:119,134`). Not a
deployment-breaking issue technically, but worth surfacing here explicitly:
if this goes in front of real clinicians/judges as a working safety
feature, the specific numeric thresholds (symptom weights, baseline-band
formula, the 0.35 pause-ratio / 0.20 energy-CV acoustic cutoffs, etc.) have
zero clinical validation behind them — they were reasoned about, tested for
internal consistency, and calibrated against synthetic audio only, never
checked against a real patient population or a clinician's sign-off.

### 13. No refresh token / session revocation — pre-existing MVP-scope decision, still true
24h JWT expiry, no refresh token, no logout-everywhere/revocation mechanism
(`Backend/app/core/config.py:25`, flagged as an explicit MVP gap since the
original 2026-08-24 auth pass). Not urgent for a short demo window, but
means a leaked or stolen token from a longer-running deployment stays valid
for a full day with no way to invalidate it early. Listed here rather than
under MUST FIX because it's a known, deliberate scope cut for this
hackathon rather than an oversight — but it should be a deliberate decision
to accept for the deployed version too, not a silent carry-over.

---

## 🟢 ACCEPTABLE AS-IS for the hackathon demo

### 14. JWT storage in the web app — `localStorage`
Confirmed still exactly as documented in `web_app/src/core/tokenStorage.js`'s
own doc comment (re-read in full this session, matches
[[decisions-log]] verbatim): a real, explicitly-flagged XSS trade-off (a
successful XSS steals the token for its full 24h life), accepted because the
safer alternative (an httpOnly cookie) needs a backend change this project's
sessions were repeatedly scoped not to make, and mitigated (not eliminated)
by React's default output-escaping — confirmed no `dangerouslySetInnerHTML`
exists anywhere in `web_app/src` (grepped fresh this session). **Acceptable
for a short-lived hackathon demo deployment** where the realistic threat
model is "judges click around a link," not "this is a long-running product
handling real patient data from the public internet." Revisit before any
use beyond a demo.

### 15. ~~Local-disk audio storage, for a demo specifically~~ — SUPERSEDED (2026-08-29), item 7 is now genuinely fixed, not just tolerated
This item argued the ephemeral-filesystem risk was tolerable for a
one-shot demo with no mid-event redeploys. That reasoning is now moot —
item 7 is fixed for real with a Railway Volume, verified to survive an
actual container destroy-and-recreate cycle (a real redeploy would no
longer lose anything). Kept here, struck through, rather than deleted, so
the reasoning trail stays visible for why this was once accepted as-is.

### 16. Demo seed password — one shared password for every seeded account
`Backend/seed.py:67` — `SEED_PASSWORD = "RozNoor@123"`, real bcrypt-hashed,
shared across every seeded demo user (Zubaida Bibi, Dr. Ayesha Farooq, Sadia
Kamran, etc.). Confirmed via `grep` it's referenced nowhere outside
`seed.py` itself — not a leaked real-user credential, it's fictional demo
data by design, meant to be known/shared so judges can log in as any seeded
role. Fine as-is; would only need changing if this seed data were ever
mistaken for real patient accounts.

### 17. `psycopg2-binary` instead of `psycopg2` built from source
Standard advice is to avoid the `-binary` package in production (bundles its
own libpq, can have ABI edge cases), but at hackathon-demo scale/traffic
this is a non-issue and switching adds real friction (needs build-time
Postgres dev headers). No action needed.

### 18. No AgentRouter references found anywhere
Searched the entire tracked codebase (`*.py`, `*.dart`, `*.js`, `*.jsx`,
`*.md`, `*.json`, `*.yaml`/`*.yml`) for any mention of "AgentRouter" — zero
hits. Nothing to remove; this concern doesn't apply to this codebase.

### 19. No leaked API keys or secrets anywhere in git
Checked the full working tree and the **entire git history across all
commits** (`git log --all -p | grep sk-ant-`) for an Anthropic key pattern —
zero hits, including from the sessions that used a real key for live AI-layer
verification (per [[decisions-log]], that key was written only to a
gitignored local `.env` and removed again afterward — confirmed the claim
holds under a fresh check, not just re-trusted from the log). `.env` was
never committed at any point in history. Broader secret-pattern scan (AWS
key shapes, generic `api_key=`/`password=` literal assignments) also came
back clean. `Backend/.env.example` correctly contains only placeholder
values, with `ANTHROPIC_API_KEY` left blank.

### 20. No hardcoded production database connection strings
The only hardcoded connection string anywhere is
`Backend/app/core/config.py:19`'s fallback default
(`postgresql+psycopg2://roznoor:roznoor@localhost:5432/roznoor`) — a
dev-only placeholder matching the pattern already accepted for
`jwt_secret_key`'s default, always overridden by the real `DATABASE_URL` env
var in any non-default environment. Not a leaked real credential (`roznoor`/
`roznoor` is a throwaway local Docker Postgres role, never a production
database). See item 11 (now ✅ fixed) for the scheme-compatibility question
this raised.

---

## Quick-reference index

| # | Item | Category |
|---|------|----------|
| 1 | `JWT_SECRET_KEY` insecure default | ✅ fixed 2026-08-29 |
| 2 | CORS middleware | ✅ fixed 2026-08-29 |
| 3 | Railway deploy config (port/migrate/ffmpeg) | ✅ fixed 2026-08-29 |
| 4 | `ffmpeg` present on deploy target | ✅ fixed 2026-08-29 |
| 5 | Frontend API base URLs — build-time plumbing | ✅ fixed 2026-08-29 |
| 6 | SPA fallback for client-side routes on static hosting | ✅ fixed 2026-08-29 |
| 7 | Local-disk audio storage — ephemeral on Railway | ✅ fixed 2026-08-29 |
| 8 | `flutter test` failure — root-caused, test-only, easy fix | 🟡 |
| 9 | Migrate/seed deploy runbook | ✅ documented 2026-08-29 (see runbook) |
| 10 | Stray test-account clutter in dev DB | 🟡 |
| 11 | `DATABASE_URL` scheme compatibility w/ Railway | ✅ fixed 2026-08-29 |
| 12 | Unreviewed clinical/acoustic thresholds | 🟡 |
| 13 | No refresh token / session revocation | 🟡 |
| 14 | Web JWT storage via `localStorage` | 🟢 |
| 15 | ~~Local-disk audio storage — demo tolerance~~ | superseded, see item 7 |
| 16 | Shared demo seed password | 🟢 |
| 17 | `psycopg2-binary` | 🟢 |
| 18 | AgentRouter — confirmed absent | 🟢 |
| 19 | No leaked secrets in git (working tree + full history) | 🟢 |
| 20 | No hardcoded prod DB strings | 🟢 |
| 21 | Chest-pain first-aid guidance panel — needs real clinical/legal sign-off | 🔴 |

**New/changed files, Tier 1 (2026-08-29, part 1)**: `Backend/Dockerfile`,
`Backend/start.sh`, `Backend/railway.json`, `Backend/.dockerignore`,
`web_app/Dockerfile`, `web_app/nginx.default.conf.template`,
`web_app/railway.json`, `web_app/.dockerignore` — plus
`Backend/app/core/config.py` (the `database_url` scheme normalizer, item
11). None touch `mobile_app/` (see item 6's Flutter-web note).

**New/changed files, Tier 2 (2026-08-29, part 2)**: `Backend/app/core/
config.py` (extended further — the `forbid_insecure_secret_outside_dev`
validator for item 1, and the `cors_allowed_origins`/
`cors_allowed_origins_list` settings for item 2), `Backend/app/main.py`
(the actual `CORSMiddleware` wiring), `Backend/.env.example` (documents
both new env vars), `web_app/Dockerfile` (added the `ARG
VITE_API_BASE_URL` build-arg plumbing for item 5). No `mobile_app/` files
changed for item 5 either — its `--dart-define` mechanism was already
correct, only unverified until this pass.

**New/changed files, part 3 (2026-08-29, final deploy prep)**:
`Backend/app/core/config.py` (the `audio_storage_dir` → `audio_storage_path`
rename + `AUDIO_STORAGE_PATH` env var, item 7), `Backend/app/routers/
entries.py` and `Backend/app/models/entry.py` (updated to the renamed
field/its doc comment), `Backend/.env.example` (documents the new var).
Plus the new "Railway deploy runbook" section above (no code — the
ordered env-var/service-setup sequence, the `seed.py` command, and the
Flutter rebuild command).

Items 1, 2, 3, 4, 5, 6, 7, and 11 are now ✅ fixed and verified
(2026-08-29) — see each item's own entry above and [[decisions-log]] for
the full verification narrative of each. Item 9 is now documented (the
runbook above), not code-changed. Items 8, 10, 12, and 13 remain
untouched, deliberately deferred to a future session. Say which of the
remaining items to act on next.
