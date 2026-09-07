"""
Schemas for the doctor-facing routers: patient roster, alerts panel, and
doctor notes. Field choices are informed by the doctor dashboard screens
in the UI prototype (`UI Inspo/.../RozNoor.dc.html`, `roster`/`alerts`/
`notes` state) — see context/decisions-log.md.
"""

from datetime import datetime

from pydantic import BaseModel, Field


class DoctorPatientRosterItem(BaseModel):
    patient_id: int
    name: str | None
    mr_number: str | None
    age: int | None
    diagnosis: str | None
    day_count: int
    baseline_stage: str
    latest_risk_level: str | None
    latest_reasoning: str | None
    last_entry_timestamp: datetime | None


class AlertOut(BaseModel):
    id: int
    patient_id: int
    patient_name: str | None
    entry_id: int | None
    risk_level: str
    alert_text: str
    source_rule: str | None
    reviewed: bool
    created_at: datetime


class DoctorNoteCreate(BaseModel):
    note_text: str = Field(min_length=1)


class DoctorNoteOut(BaseModel):
    id: int
    patient_id: int
    doctor_id: int
    doctor_name: str | None
    note_text: str
    created_at: datetime
