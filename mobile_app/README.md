# RozNoor — Patient Mobile App

Flutter app for the patient/attendant role. Voice Diary, Quick Check-in, Result,
Timeline, Weekly Trends, and Profile screens, wired to the FastAPI backend in
`../Backend`. Doctor/admin screens are a later phase — see
`../context/conventions.md`.

## Run locally (Linux desktop / same-machine testing)

1. Start the backend (`../Backend`, see its own README/`.env.example`) and confirm
   `GET /health` responds.
2. `flutter pub get`
3. `flutter run -d linux` — the default `http://localhost:8000` works fine here.

## Run on a real device / emulator (over LAN)

A phone or emulator can't reach the dev machine at `localhost` — see
`../context/conventions.md` ("Running the phone app on the real backend over
LAN") for the full explanation. Three things, every time the dev machine's IP
might have changed:

1. **Backend**: run it bound to all interfaces, not just loopback —
   `uvicorn app.main:app --host 0.0.0.0 --port 8000` (from `Backend/`, venv
   active).
2. **Find the dev machine's LAN IP**: `hostname -I` (use the WiFi/LAN
   interface address, e.g. `192.168.x.x` — not a `docker0`/`br-*` one).
3. **Run the app pointed at it**:
   ```
   flutter run -d <device-id> --dart-define=ROZNOOR_API_BASE_URL=http://<that-ip>:8000
   ```
   (`flutter devices` lists `<device-id>`.) An Android *emulator* (not a real
   device) can instead use the fixed alias `10.0.2.2` in place of the LAN IP.

Real Android devices additionally need debug builds to allow plain-HTTP
traffic to a non-TLS backend — already handled by
`android/app/src/debug/res/xml/network_security_config.xml`, debug-only, no
action needed unless that file is removed.

Demo login (any seeded patient/attendant, see `Backend/seed.py`):
`zubaida.b@roznoor.care` / `RozNoor@123`.

See `../context/decisions-log.md` and `../context/conventions.md` for the
design/architecture decisions behind this app.
