# RozNoor — Patient Web App

React + Vite web app for the patient/attendant role, mirroring
`mobile_app/` (Flutter) against the same FastAPI backend. Doctor/admin web
screens are not built yet — see `context/progress.md`.

## Run it

```bash
# 1. Backend (from Backend/, with its venv active and roznoor-pg running)
uvicorn app.main:app --host 0.0.0.0 --port 8000

# 2. This app
npm install
npm run dev   # http://localhost:5173
```

No `.env` needed for local dev — see `vite.config.js`: the dev server
proxies every backend path (`/auth`, `/patients`, `/entries`, `/doctors`,
`/alerts`, `/admin`, `/health`) to `http://localhost:8000`, so the browser
only ever talks to its own origin (no CORS setup needed on the backend —
see `context/decisions-log.md`, "web app CORS/proxy decision"). Point at a
different backend with `VITE_API_BASE_URL=http://host:port npm run dev`.

Seeded patient login: `zubaida.b@roznoor.care` / `RozNoor@123`. Clinician
accounts route to a placeholder — see `context/conventions.md`.

## Structure

See `context/conventions.md` ("React web app (`web_app/`)") for the full
file-by-file breakdown and how it maps to `mobile_app/`.
