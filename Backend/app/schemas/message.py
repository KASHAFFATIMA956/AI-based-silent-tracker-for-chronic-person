"""
Schemas for GET/POST /patients/{patient_id}/messages — direct messaging
between a patient (or their attendant) and their assigned doctor. Added
2026-09-07 (direct-messaging pass) — see context/decisions-log.md.

content is bounds-checked the same "generous sanity check, not a real
product limit" spirit as every other free-text field's length bound in
this app (e.g. DoctorNoteCreate has none, but a chat message is
user-facing/repeatedly-sent in a way a clinical note isn't, so a cap here
guards against a runaway client bug rather than a real conversation).
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class MessageCreate(BaseModel):
    content: str = Field(min_length=1, max_length=4000)


class MessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=False)

    id: int
    patient_id: int
    sender_user_id: int
    sender_role: str  # patient | attendant | doctor
    # Computed via a lookup, same "not a plain column" pattern as
    # DoctorNoteOut.doctor_name / PatientOut.assigned_doctor_name.
    sender_name: str | None
    content: str
    created_at: datetime
    # Always null for now — see app/models/message.py's docstring. Exposed
    # here because the task's own schema spec calls for the column, not
    # because anything currently sets it.
    read_at: datetime | None
