"""
Doctor-facing routers: patient roster, alerts panel + review, and
clinical notes. Two APIRouters in this one file since the paths don't
share a single prefix:
  - `router` (prefix /doctors)  — GET /doctors/{doctor_id}/patients,
    GET /doctors/{doctor_id}/alerts
  - `alerts_router` (prefix /alerts) — POST /alerts/{alert_id}/review
Doctor notes (POST/GET /patients/{patient_id}/notes) live in
app/routers/patients.py instead, since that prefix already exists there.

RBAC:
  - GET /doctors/{doctor_id}/patients, GET /doctors/{doctor_id}/alerts:
    `get_authorized_doctor` (doctor self, or admin).
  - POST /alerts/{alert_id}/review: `require_roles(doctor, admin)` +
    `is_authorized_clinician_for_patient` (doctor must be the alert's
    patient's assigned doctor; admin always allowed).
See app/core/deps.py for both dependencies — no parallel auth logic here.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import (
    get_authorized_doctor,
    is_authorized_clinician_for_patient,
    require_roles,
)
from app.models.alert import Alert
from app.models.entry import Entry
from app.models.enums import UserRole
from app.models.patient import Patient
from app.models.risk_result import RiskResult
from app.models.user import User
from app.schemas.doctor import AlertOut, DoctorPatientRosterItem

router = APIRouter(prefix="/doctors", tags=["doctors"])
alerts_router = APIRouter(prefix="/alerts", tags=["alerts"])


def _patient_display_name(db: Session, patient: Patient) -> str | None:
    if patient.user_id is None:
        return None
    user = db.get(User, patient.user_id)
    return user.name if user else None


def _alert_out(db: Session, alert: Alert, patient: Patient | None = None) -> AlertOut:
    if patient is None:
        patient = db.get(Patient, alert.patient_id)
    return AlertOut(
        id=alert.id,
        patient_id=alert.patient_id,
        patient_name=_patient_display_name(db, patient) if patient else None,
        entry_id=alert.entry_id,
        risk_level=alert.risk_level.value,
        alert_text=alert.alert_text,
        source_rule=alert.source_rule,
        reviewed=alert.reviewed,
        created_at=alert.created_at,
    )


@router.get("/{doctor_id}/patients", response_model=list[DoctorPatientRosterItem])
def get_doctor_patients(
    doctor: User = Depends(get_authorized_doctor),
    db: Session = Depends(get_db),
) -> list[DoctorPatientRosterItem]:
    patients = db.query(Patient).filter(Patient.assigned_doctor_id == doctor.id).all()

    results: list[DoctorPatientRosterItem] = []
    for patient in patients:
        latest_entry = (
            db.query(Entry)
            .filter(Entry.patient_id == patient.id)
            .order_by(Entry.timestamp.desc())
            .first()
        )
        latest_risk_level = None
        latest_reasoning = None
        if latest_entry is not None:
            risk = db.query(RiskResult).filter(RiskResult.entry_id == latest_entry.id).first()
            if risk is not None:
                latest_risk_level = risk.risk_level.value
                latest_reasoning = risk.reasoning

        results.append(
            DoctorPatientRosterItem(
                patient_id=patient.id,
                name=_patient_display_name(db, patient),
                mr_number=patient.mr_number,
                age=patient.age,
                diagnosis=patient.diagnosis,
                day_count=patient.day_count,
                baseline_stage=patient.baseline_stage.value,
                latest_risk_level=latest_risk_level,
                latest_reasoning=latest_reasoning,
                last_entry_timestamp=latest_entry.timestamp if latest_entry else None,
            )
        )

    # Most recently active patient first — most useful ordering for a
    # doctor scanning their roster; patients with no entries yet sort last.
    with_entry = sorted(
        (r for r in results if r.last_entry_timestamp is not None),
        key=lambda r: r.last_entry_timestamp,
        reverse=True,
    )
    without_entry = [r for r in results if r.last_entry_timestamp is None]
    return with_entry + without_entry


@router.get("/{doctor_id}/alerts", response_model=list[AlertOut])
def get_doctor_alerts(
    reviewed: bool | None = Query(default=None, description="Filter by reviewed status"),
    doctor: User = Depends(get_authorized_doctor),
    db: Session = Depends(get_db),
) -> list[AlertOut]:
    patient_ids = [
        pid for (pid,) in db.query(Patient.id).filter(Patient.assigned_doctor_id == doctor.id)
    ]
    query = db.query(Alert).filter(Alert.patient_id.in_(patient_ids))
    if reviewed is not None:
        query = query.filter(Alert.reviewed == reviewed)
    alerts = query.order_by(Alert.created_at.desc()).all()

    patients_by_id = {p.id: p for p in db.query(Patient).filter(Patient.id.in_(patient_ids))}
    return [_alert_out(db, a, patients_by_id.get(a.patient_id)) for a in alerts]


@alerts_router.post("/{alert_id}/review", response_model=AlertOut)
def review_alert(
    alert_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.doctor, UserRole.admin)),
) -> AlertOut:
    alert = db.get(Alert, alert_id)
    if alert is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert not found")

    patient = db.get(Patient, alert.patient_id)
    if patient is None or not is_authorized_clinician_for_patient(current_user, patient):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to review this alert",
        )

    alert.reviewed = True
    db.commit()
    db.refresh(alert)
    return _alert_out(db, alert, patient)
