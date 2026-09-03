"""
Reusable FastAPI dependencies for authentication and role-based access
control (RBAC).

- get_current_user: extracts + verifies the Bearer JWT, loads the User.
- require_roles(*roles): dependency factory — 403s if current_user.role
  isn't one of the given roles.
- get_authorized_patient: dependency for any route with a {patient_id}
  path param — loads the Patient and 403s unless the current user is
  allowed to see it:
    * admin           -> always allowed
    * doctor          -> allowed if patients.assigned_doctor_id == self
    * patient         -> allowed if patients.user_id == self
    * attendant       -> allowed if patients.attendant_user_id == self
      (attendant access wasn't spelled out in the task's RBAC list, but
      the schema already models attendant-managed patients via
      attendant_user_id, so leaving attendants with no access at all
      would be inconsistent with the schema/product. Confirmed correct
      by the user 2026-08-25 — see context/decisions-log.md.)
- get_authorized_doctor: dependency for any route with a {doctor_id} path
  param (doctor's own roster/alerts) — admin always allowed, doctor only
  for their own doctor_id. Narrower than get_authorized_patient: no
  patient/attendant access at all, since these are doctor-scoped resources.
- get_clinician_patient: dependency for doctor/admin-ONLY patient-scoped
  routes (doctor notes) — role-gates to doctor/admin via require_roles,
  then admin always allowed, doctor only if they're this patient's
  assigned_doctor_id. Deliberately excludes the patient/attendant
  self-access that get_authorized_patient allows — see
  context/decisions-log.md for why doctor_notes is clinician-only.
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

import jwt

from app.core.database import get_db
from app.core.security import decode_access_token
from app.models.enums import UserRole
from app.models.patient import Patient
from app.models.user import User

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Not authenticated",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized

    try:
        payload = decode_access_token(credentials.credentials)
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError:
        raise unauthorized

    user_id = payload.get("sub")
    if user_id is None:
        raise unauthorized

    user = db.get(User, int(user_id))
    if user is None:
        raise unauthorized

    return user


def require_roles(*roles: UserRole):
    """Dependency factory: 403s unless current_user.role is one of `roles`."""

    def dependency(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized for this action",
            )
        return current_user

    return dependency


def is_authorized_for_patient(current_user: User, patient: Patient) -> bool:
    """
    The RBAC rule itself, factored out so both path-param routes
    (via get_authorized_patient below) and body-param routes (e.g.
    POST /entries, where patient_id comes from the request body, not the
    URL) can enforce the same policy without duplicating it.
    """
    role = current_user.role
    return (
        role == UserRole.admin
        or (role == UserRole.doctor and patient.assigned_doctor_id == current_user.id)
        or (role == UserRole.patient and patient.user_id == current_user.id)
        or (role == UserRole.attendant and patient.attendant_user_id == current_user.id)
    )


def get_authorized_patient(
    patient_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Patient:
    """Route dependency: resolves {patient_id} to a Patient, enforcing RBAC."""
    patient = db.get(Patient, patient_id)
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")

    if not is_authorized_for_patient(current_user, patient):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this patient",
        )
    return patient


def is_authorized_for_doctor(current_user: User, doctor_id: int) -> bool:
    """
    RBAC for doctor-scoped resources (GET /doctors/{doctor_id}/patients,
    GET /doctors/{doctor_id}/alerts): a doctor may only see their OWN
    roster/alerts; admin can see any doctor's.
    """
    role = current_user.role
    return role == UserRole.admin or (role == UserRole.doctor and current_user.id == doctor_id)


def get_authorized_doctor(
    doctor_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> User:
    """Route dependency: resolves {doctor_id} to a doctor User, enforcing RBAC."""
    doctor = db.get(User, doctor_id)
    if doctor is None or doctor.role != UserRole.doctor:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Doctor not found")

    if not is_authorized_for_doctor(current_user, doctor_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this doctor's data",
        )
    return doctor


def is_authorized_clinician_for_patient(current_user: User, patient: Patient) -> bool:
    """
    RBAC for doctor/admin-ONLY, patient-scoped write actions (doctor notes,
    alert review): admin always; doctor only if they're this patient's
    assigned_doctor_id. Deliberately narrower than is_authorized_for_patient
    (which also allows the patient/attendant themselves) — those roles can
    read their own record but must not write clinical notes or mark alerts
    reviewed.
    """
    role = current_user.role
    return role == UserRole.admin or (
        role == UserRole.doctor and patient.assigned_doctor_id == current_user.id
    )


def get_clinician_patient(
    patient_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.doctor, UserRole.admin)),
) -> Patient:
    """
    Route dependency for doctor/admin-only patient-scoped routes (doctor
    notes). Role-gates to doctor/admin first, then enforces assigned-
    doctor-or-admin ownership via is_authorized_clinician_for_patient.
    """
    patient = db.get(Patient, patient_id)
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")

    if not is_authorized_clinician_for_patient(current_user, patient):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to manage this patient's clinical notes",
        )
    return patient
