# AI based silent tracker for chronic person


AI based silent tracker for chronic person is a remote patient-monitoring system for post-discharge heart-failure
and post-surgical patients. Patients log daily check-ins (voice or quick-tap)
from a mobile app; a deterministic rule engine — optionally supported by an AI
interpretation layer — turns each entry into a Green/Yellow/Orange/Red risk
result, and non-Green results surface to the patient's doctor as alerts.

Built for a hackathon submission.

## How it works

1. **Patient check-in** (voice diary or quick check-in) hits `POST /entries`.
2. A **rule engine** (`app/services/rules.py`) evaluates the entry against
   diagnosis-specific hard red-flags (e.g. chest pain, a rapid weight gain)
   and a weighted score built from symptoms, baseline deviation, and
   medication adherence. This layer has no AI dependency and always runs.
3. For **voice entries**, Claude first extracts which checklist symptoms the
   transcript describes (`app/services/ai.py`); those matches are folded into
   the same symptom set the rule engine scores — AI never assigns risk on its
   own, it only supplies evidence into the deterministic engine.
4. An optional **acoustic-signal pass** (`app/services/audio_analysis.py`,
   pure numpy + ffmpeg signal processing — not a machine-learning model) can
   attach a pause-ratio / vocal-energy pattern as an additional, capped signal
   once a recording is uploaded.
5. Non-Green results create an **alert**, visible to the patient's assigned
   doctor.

Every threshold in the rule engine and acoustic layer that isn't sourced
directly from the project's clinical documentation is explicitly flagged as a
proposal needing review — see `context/decisions-log.md`.

## Repository layout

```
Backend/      FastAPI backend — auth, rules engine, AI layer, doctor/admin
              routers, Alembic migrations, seed data
mobile_app/   Flutter app (patient/attendant role) — voice diary, quick
              check-in, timeline, weekly digest, profile
docs/         Original project/design documents
UI Inspo/     Design prototype (RozNoor.dc.html) used as the visual/content
              source for screens not yet built natively
context/      Living project memory — schema, API contracts, conventions,
              decisions log, and progress tracking, updated as work happens
```

## Backend setup

Requires Python 3.11+, PostgreSQL, and `ffmpeg` on `PATH` (used by the
acoustic-analysis pass to decode uploaded recordings).

```bash
cd Backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# edit .env: DATABASE_URL, JWT_SECRET_KEY, and (optional) ANTHROPIC_API_KEY
# — the app runs fully on its rule-only fallback with no API key configured.

alembic upgrade head
python seed.py        # safe to re-run — clears and re-seeds demo data

uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

`--host 0.0.0.0` is required for a phone on the same network to reach it —
see `context/conventions.md` for the full real-device testing setup
(LAN IP, Android cleartext-traffic config for a TLS-less dev backend, etc.).

Demo login (seeded): any seeded account's email + password `RozNoor@123`,
e.g. `zubaida.b@roznoor.care`.

## Mobile app setup

Requires Flutter (stable channel).

```bash
cd mobile_app
flutter pub get
flutter run -d <device-id> --dart-define=ROZNOOR_API_BASE_URL=http://<backend-host>:8000
```

Find your dev machine's LAN IP with `hostname -I` when testing on a real
device over WiFi; an Android emulator instead uses `10.0.2.2` for the host's
`localhost`.

## Documentation

- `context/schema.md` — database schema as implemented
- `context/api-contracts.md` — every endpoint's request/response shape
- `context/conventions.md` — folder structure, coding conventions, RBAC
  patterns, Flutter architecture
- `context/decisions-log.md` — design decisions and their rationale, newest
  first
- `context/progress.md` — what's built, what's verified, what's open

## License

MIT — see [LICENSE](LICENSE).
