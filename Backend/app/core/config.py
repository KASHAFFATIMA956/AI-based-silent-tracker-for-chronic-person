"""
Application configuration.

Reads settings from environment variables / a .env file. The only
required value to run against a real database is DATABASE_URL, which
should point at a PostgreSQL instance (Railway/Neon/Supabase-compatible).

See docs/RozNoor_Database_Schema_and_Deployment_Plan.docx section 1-2 for
why Postgres + Railway were chosen over SQLite/VPS alternatives.
"""

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# The literal insecure default below — pulled out to a module constant so
# the "is this still the default?" check (in the validator further down)
# can never silently drift out of sync with the field itself.
_INSECURE_DEFAULT_JWT_SECRET = "insecure-dev-only-secret-change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # e.g. postgresql+psycopg2://user:password@host:port/dbname
    database_url: str = "postgresql+psycopg2://roznoor:roznoor@localhost:5432/roznoor"

    @field_validator("database_url")
    @classmethod
    def normalize_database_url_scheme(cls, v: str) -> str:
        """Railway (and other hosts) inject DATABASE_URL with a bare
        `postgres://` or `postgresql://` scheme, never the explicit
        `+psycopg2` driver suffix this app's own default/docs use.
        SQLAlchemy 2.0 silently accepts `postgresql://` (defaults to the
        installed psycopg2 driver) but hard-FAILS on the legacy
        `postgres://` scheme with `NoSuchModuleError: Can't load plugin:
        sqlalchemy.dialects:postgres` — confirmed directly against this
        app's actual installed sqlalchemy==2.0.52 before writing this,
        not assumed. Normalizing both to `postgresql+psycopg2://` here
        means whatever scheme a host injects always works, without every
        caller needing to know this quirk. A URL that already specifies a
        driver (e.g. `postgresql+psycopg2://`, or a hypothetical
        `+psycopg://`) is left untouched. See context/decisions-log.md.
        """
        if v.startswith("postgres://"):
            v = "postgresql://" + v[len("postgres://") :]
        if v.startswith("postgresql://"):
            v = "postgresql+psycopg2://" + v[len("postgresql://") :]
        return v

    app_name: str = "RozNoor API"
    # Set ENVIRONMENT=production on Railway (or anything other than the
    # default "development") — this is what the jwt_secret_key safeguard
    # below keys off. Also already returned by GET /health, useful for
    # confirming which mode a deployed instance actually thinks it's in.
    environment: str = "development"

    # JWT auth. jwt_secret_key MUST be overridden via env var outside local
    # dev/hackathon use — this default is intentionally insecure. See the
    # forbid_insecure_secret_outside_dev validator below: this is enforced,
    # not just documented — the app refuses to start rather than silently
    # running with it once ENVIRONMENT isn't "development".
    jwt_secret_key: str = _INSECURE_DEFAULT_JWT_SECRET
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24  # 24h — no refresh token in this MVP

    @model_validator(mode="after")
    def forbid_insecure_secret_outside_dev(self) -> "Settings":
        """The insecure default is a local-dev-only fallback, not something
        that should ever be reachable in a real deploy — a leaked/guessable
        JWT secret lets anyone forge a valid token for any user/role
        (including admin). Rather than trust every future session/deployer
        to remember to set JWT_SECRET_KEY, this makes forgetting it a hard
        startup failure instead of a silent security hole: once
        ENVIRONMENT is anything other than "development" (set
        ENVIRONMENT=production on Railway), booting with the still-default
        secret raises here, before the app can serve a single request.
        Local dev is unaffected — ENVIRONMENT defaults to "development" and
        this validator is a no-op there, same as it's always behaved. See
        context/decisions-log.md and context/pre-deployment-checklist.md
        item 1.
        """
        if self.environment != "development" and self.jwt_secret_key == _INSECURE_DEFAULT_JWT_SECRET:
            raise ValueError(
                "JWT_SECRET_KEY is still the insecure local-dev default "
                f"outside a development ENVIRONMENT (current: {self.environment!r}). "
                "Set a real JWT_SECRET_KEY (e.g. `openssl rand -hex 32`) "
                "before deploying — refusing to start with it."
            )
        return self

    # CORS. Comma-separated list of EXACT allowed origins — deliberately
    # never a wildcard "*" (this is a health app; cross-origin requests
    # should only ever come from this project's own deployed frontend(s),
    # see context/pre-deployment-checklist.md item 2). Defaults cover
    # Vite's own dev port on both localhost/127.0.0.1 so a `vite dev`
    # frontend pointed directly at this backend (VITE_API_BASE_URL set,
    # bypassing vite.config.js's own dev-proxy) still works without extra
    # local setup. Set CORS_ALLOWED_ORIGINS on Railway to the real deployed
    # frontend origin(s) once known, e.g.
    # "https://roznoor-web.up.railway.app" — comma-separate multiple
    # origins (a custom domain alongside the *.up.railway.app one, say).
    cors_allowed_origins: str = "http://localhost:5173,http://127.0.0.1:5173"

    @property
    def cors_allowed_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_allowed_origins.split(",") if origin.strip()]

    # Claude API. None (unset) is a valid, expected state — app.services.ai
    # treats a missing key as "AI unavailable" and every caller falls back
    # to the rule engine alone, per the documented fallback requirement.
    # Never hardcode a key here; set ANTHROPIC_API_KEY in the environment.
    anthropic_api_key: str | None = None

    # Voice Diary audio uploads (added 2026-08-25, acoustic-analysis pass).
    # Env var AUDIO_STORAGE_PATH. Defaults to a plain relative path
    # ("audio_storage", relative to Backend/'s cwd) for local dev — the
    # exact same default/behavior as before this field was made
    # configurable. On Railway, set this to a path INSIDE a mounted
    # Volume, e.g. AUDIO_STORAGE_PATH=/data/audio_storage (with the
    # Volume itself mounted at /data) — see
    # context/pre-deployment-checklist.md item 7 for why a Volume (not
    # cloud/S3 storage) is the right-sized fix here, and the exact Railway
    # setup steps. Still local-disk storage either way (still not
    # multi-instance safe — a Volume attaches to exactly one service, so
    # this remains a single-backend-instance design, fine for this
    # project's scale) — what a Volume actually buys is surviving a
    # redeploy/restart, which a container's own ephemeral filesystem does
    # not. `os.path.join`/`os.makedirs` in app/routers/entries.py work
    # identically whether this is relative (dev) or an absolute mount path
    # (prod) — no other code change was needed for this.
    audio_storage_path: str = "audio_storage"


settings = Settings()
