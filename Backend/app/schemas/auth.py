from pydantic import BaseModel


class LoginRequest(BaseModel):
    phone_or_email: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds
    user_id: int
    role: str
    name: str


class CurrentUserResponse(BaseModel):
    id: int
    name: str
    role: str
    phone_or_email: str
    language_preference: str
    # The caller's own patients.id, when role is patient (patients.user_id
    # match) or attendant (patients.attendant_user_id match) — None for
    # doctor/admin, or a patient/attendant not yet linked to a Patient row.
    # Added 2026-08-25 (Flutter patient-app pass): no client-facing endpoint
    # otherwise lets a freshly-logged-in patient/attendant discover their own
    # patient_id to call every patient-scoped route with — see
    # context/decisions-log.md.
    patient_id: int | None = None
