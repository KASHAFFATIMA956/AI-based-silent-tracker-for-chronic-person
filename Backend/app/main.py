"""
FastAPI app entrypoint.

Routers: auth (login/me), patients (get + AI summary + doctor notes),
entries (check-in submission + timeline, with the rule engine and
optional AI layer wired in), doctors (roster + alerts panel + alert
review), admin (People & roles management). This is the full backend
scope for the hackathon MVP — see context/progress.md.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import admin, auth, doctors, entries, patients

app = FastAPI(title=settings.app_name)

# CORS — real middleware, not the Vite dev-proxy workaround `web_app`'s own
# sessions relied on (that proxy only exists inside `vite dev`'s process;
# a production static build has no server behind it to route around the
# browser's same-origin policy). Allowed origins come from
# settings.cors_allowed_origins_list (env var CORS_ALLOWED_ORIGINS,
# comma-separated) — deliberately never a wildcard, see that field's own
# comment in app/core/config.py. allow_credentials=False: this app's auth
# is a Bearer token in an Authorization header (web_app/src/core/
# tokenStorage.js — localStorage, not a cookie), which CORS does not treat
# as a "credential" the way cookies/TLS-client-certs are — no cookie-based
# session exists anywhere in this app for allow_credentials to matter to.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allowed_origins_list,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(patients.router)
app.include_router(entries.router)
app.include_router(doctors.router)
app.include_router(doctors.alerts_router)
app.include_router(admin.router)


@app.get("/health")
def health():
    return {"status": "ok", "environment": settings.environment}
