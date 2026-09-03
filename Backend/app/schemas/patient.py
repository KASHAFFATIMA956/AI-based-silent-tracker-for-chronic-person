"""
Read schema for Patient. Originally a minimal RBAC-proof shape (id,
mr_number, diagnosis, age, baseline_stage, day_count, the three FK ids);
extended 2026-08-25 (Flutter patient-app pass) with fields the Profile
screen needs that already existed as real columns/relations but weren't
exposed yet: emergency_contact_name/phone and medication_info (plain
columns on patients — see context/schema.md), plus attendant_name and
assigned_doctor_name (computed via a join, same pattern as the admin
router's linked_summary — see context/decisions-log.md). Still no
create/update schema — there is no PATCH /patients/{id}; Profile stays
view-only for these fields (see context/decisions-log.md).
"""

from pydantic import BaseModel, ConfigDict


class PatientOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    mr_number: str | None
    diagnosis: str | None
    age: int | None
    baseline_stage: str
    day_count: int
    assigned_doctor_id: int | None
    user_id: int | None
    attendant_user_id: int | None
    emergency_contact_name: str | None
    emergency_contact_phone: str | None
    medication_info: str | None
    # Computed, not a plain column — see routers/patients.py.
    attendant_name: str | None = None
    assigned_doctor_name: str | None = None


class SymptomChecklistItem(BaseModel):
    """
    One symptom_checklist_options row, for GET /patients/{id}/symptom-checklist
    — added 2026-08-25 (Flutter patient-app pass) so the Quick Check-in /
    Voice Diary screens can render the diagnosis-specific checklist instead
    of a hardcoded one. See context/decisions-log.md.
    """

    model_config = ConfigDict(from_attributes=True)

    id: int
    symptom_name: str
