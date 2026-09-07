"""
Schemas for the admin "People & roles" router (app/routers/admin.py).

No `status` (Active/Invited) field: the users table has no such column and
none was added for this pass (see context/decisions-log.md) — the UI
prototype's status badge is decorative demo dressing with no persisted
state behind it. `AdminUserUpdate` only ever edits columns that actually
exist (name/role/phone_or_email/language_preference).
"""

from datetime import datetime

from pydantic import BaseModel, model_validator

from app.models.enums import LanguagePreference, UserRole


class AdminUserOut(BaseModel):
    id: int
    name: str
    role: str
    phone_or_email: str
    language_preference: str
    created_at: datetime
    # Short human-readable summary of who/what this user is linked to —
    # a doctor's patient count, an attendant's linked patient, a patient's
    # assigned doctor, or "System" for admin. None if not yet linked.
    linked_summary: str | None = None
    # A patient's diagnosis ("disease track" in the UI prototype); None
    # for non-patient roles or a patient with no diagnosis set yet.
    diagnosis: str | None = None


class AdminUserCreate(BaseModel):
    name: str
    role: UserRole
    phone_or_email: str
    password: str
    language_preference: LanguagePreference = LanguagePreference.english


class AdminUserUpdate(BaseModel):
    name: str | None = None
    role: UserRole | None = None
    phone_or_email: str | None = None
    language_preference: LanguagePreference | None = None

    @model_validator(mode="after")
    def _check_at_least_one_field(self):
        if all(
            v is None
            for v in (self.name, self.role, self.phone_or_email, self.language_preference)
        ):
            raise ValueError("at least one field must be provided to update")
        return self
