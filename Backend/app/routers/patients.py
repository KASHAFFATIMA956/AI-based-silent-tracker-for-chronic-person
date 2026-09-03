"""
Patients router. GET /{patient_id} exists to exercise the RBAC dependency
(get_authorized_patient) end-to-end — full patient CRUD/list endpoints
are a separate, later task.

POST /{patient_id}/ai-summary is the "Generate AI Summary" doctor-facing
button from the project doc/UI prototype (also usable for the patient's
own Result-screen-style summary, same RBAC as everything else patient-
scoped). Soft-fails to available=false, never a 500, if the Claude API
is unavailable — see app/services/ai.py's fallback contract.

POST/GET /{patient_id}/notes are doctor_notes — doctor/admin ONLY (not
patient/attendant self-access, unlike everything else in this router),
via app.core.deps.get_clinician_patient. See context/decisions-log.md.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_authorized_patient, get_clinician_patient, get_current_user
from app.models.ai_result import AiResult
from app.models.baseline_history import BaselineHistory
from app.models.doctor_note import DoctorNote
from app.models.entry import Entry
from app.models.patient import Patient
from app.models.symptom_checklist_option import SymptomChecklistOption
from app.models.user import User
from app.schemas.ai import AiSummaryOut
from app.schemas.doctor import DoctorNoteCreate, DoctorNoteOut
from app.schemas.patient import PatientOut, SymptomChecklistItem
from app.services import ai as ai_service
from app.services import rules as rules_service

router = APIRouter(prefix="/patients", tags=["patients"])

# How many of the patient's most recent entries feed the summary prompt.
SUMMARY_ENTRY_LOOKBACK = 10

_FALLBACK_MESSAGE = (
    "AI summary is unavailable right now (Claude API unreachable or not "
    "configured). Rule-based risk data for this patient is unaffected and "
    "still up to date."
)


@router.get("/{patient_id}", response_model=PatientOut)
def get_patient(
    patient: Patient = Depends(get_authorized_patient),
    db: Session = Depends(get_db),
) -> PatientOut:
    # attendant_name / assigned_doctor_name: cheap one-off lookups, same
    # "computed, not stored" pattern as admin.py's linked_summary — see
    # context/decisions-log.md.
    attendant_name = None
    if patient.attendant_user_id:
        attendant = db.query(User).filter(User.id == patient.attendant_user_id).first()
        attendant_name = attendant.name if attendant else None

    assigned_doctor_name = None
    if patient.assigned_doctor_id:
        doctor = db.query(User).filter(User.id == patient.assigned_doctor_id).first()
        assigned_doctor_name = doctor.name if doctor else None

    return PatientOut(
        id=patient.id,
        mr_number=patient.mr_number,
        diagnosis=patient.diagnosis,
        age=patient.age,
        baseline_stage=patient.baseline_stage.value,
        day_count=patient.day_count,
        assigned_doctor_id=patient.assigned_doctor_id,
        user_id=patient.user_id,
        attendant_user_id=patient.attendant_user_id,
        emergency_contact_name=patient.emergency_contact_name,
        emergency_contact_phone=patient.emergency_contact_phone,
        medication_info=patient.medication_info,
        attendant_name=attendant_name,
        assigned_doctor_name=assigned_doctor_name,
    )


@router.get("/{patient_id}/symptom-checklist", response_model=list[SymptomChecklistItem])
def get_symptom_checklist(
    patient: Patient = Depends(get_authorized_patient),
    db: Session = Depends(get_db),
) -> list[SymptomChecklistOption]:
    # Same diagnosis -> checklist lookup POST /entries already uses
    # (app.services.rules.CHECKLIST_DIAGNOSIS_SEARCH_TERMS +
    # diagnosis_key's normalization) — kept identical so the checklist a
    # patient sees is always the same set POST /entries will actually
    # accept symptom_ids from. Empty list for a diagnosis with no defined
    # checklist (the generic ruleset) — not an error.
    ruleset_key = rules_service.diagnosis_key(patient.diagnosis)
    search_term = rules_service.CHECKLIST_DIAGNOSIS_SEARCH_TERMS.get(ruleset_key)
    if search_term is None:
        return []
    return (
        db.query(SymptomChecklistOption)
        .filter(SymptomChecklistOption.diagnosis.ilike(f"%{search_term}%"))
        .order_by(SymptomChecklistOption.id)
        .all()
    )


@router.post("/{patient_id}/ai-summary", response_model=AiSummaryOut)
def generate_ai_summary(
    patient: Patient = Depends(get_authorized_patient),
    db: Session = Depends(get_db),
) -> AiSummaryOut:
    entries = (
        db.query(Entry)
        .filter(Entry.patient_id == patient.id)
        .order_by(Entry.timestamp.desc())
        .limit(SUMMARY_ENTRY_LOOKBACK)
        .all()
    )
    baseline_rows = {
        row.metric: row
        for row in db.query(BaselineHistory).filter(BaselineHistory.patient_id == patient.id)
    }
    # acoustic_features per entry (added 2026-08-25) — purely additive
    # prompt context so the summary can reference a real voice recording's
    # signal-processing estimate when one exists; see app/services/ai.py.
    entry_ids = [e.id for e in entries]
    acoustic_by_entry = {
        row.entry_id: row.acoustic_features
        for row in db.query(AiResult).filter(
            AiResult.entry_id.in_(entry_ids), AiResult.acoustic_features.isnot(None)
        )
    } if entry_ids else {}

    patient_user = db.get(User, patient.user_id) if patient.user_id else None
    patient_name = patient_user.name if patient_user else (patient.mr_number or f"Patient {patient.id}")
    summary_text = ai_service.generate_patient_summary(
        patient_name=patient_name,
        diagnosis=patient.diagnosis,
        entries=entries,
        baseline_rows=baseline_rows,
        acoustic_by_entry=acoustic_by_entry,
    )

    if summary_text is None:
        return AiSummaryOut(available=False, fallback_message=_FALLBACK_MESSAGE)
    return AiSummaryOut(available=True, summary_text=summary_text)


def _note_out(db: Session, note: DoctorNote) -> DoctorNoteOut:
    doctor = db.get(User, note.doctor_id)
    return DoctorNoteOut(
        id=note.id,
        patient_id=note.patient_id,
        doctor_id=note.doctor_id,
        doctor_name=doctor.name if doctor else None,
        note_text=note.note_text,
        created_at=note.created_at,
    )


@router.post("/{patient_id}/notes", response_model=DoctorNoteOut, status_code=201)
def create_note(
    payload: DoctorNoteCreate,
    patient: Patient = Depends(get_clinician_patient),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DoctorNoteOut:
    # doctor_id is expected (not DB-enforced) to reference a role=doctor
    # user, same convention as patients.assigned_doctor_id — an admin
    # authoring a note is allowed by RBAC (get_clinician_patient) and
    # recorded under their own user id, same pattern used elsewhere for
    # admin-on-behalf-of-doctor actions.
    note = DoctorNote(
        patient_id=patient.id,
        doctor_id=current_user.id,
        note_text=payload.note_text,
    )
    db.add(note)
    db.commit()
    db.refresh(note)
    return _note_out(db, note)


@router.get("/{patient_id}/notes", response_model=list[DoctorNoteOut])
def list_notes(
    patient: Patient = Depends(get_clinician_patient),
    db: Session = Depends(get_db),
) -> list[DoctorNoteOut]:
    notes = (
        db.query(DoctorNote)
        .filter(DoctorNote.patient_id == patient.id)
        .order_by(DoctorNote.created_at.desc())
        .all()
    )
    return [_note_out(db, n) for n in notes]
