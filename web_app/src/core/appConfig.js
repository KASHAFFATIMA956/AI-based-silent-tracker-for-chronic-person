// App-wide config. Mirrors mobile_app/lib/core/app_config.dart's role —
// single source of truth for the backend base URL.
//
// Deliberately EMPTY by default (a relative path, e.g. fetch('/auth/login'))
// rather than 'http://localhost:8000' — see vite.config.js and
// context/decisions-log.md ("web app CORS/proxy decision"). An empty base
// means every request stays same-origin against the Vite dev server, which
// proxies it server-side to the real backend with no CORS involved at all.
// Set VITE_API_BASE_URL only if pointing directly at a backend that already
// has CORS configured (not the case for this project's backend today).
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? ''
