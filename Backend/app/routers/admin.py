"""
Admin router: the "People & roles" management screen from the UI
prototype. Every route here is admin-only (`require_roles(UserRole.admin)`)
— no parallel auth logic, reuses the same dependency factory as every
other role-gated route in this app.

No `status` (Active/Invited) field anywhere here: the `users` table has no
such column, and PATCH /admin/users/{id} only ever edits columns that
actually exist (name/role/phone_or_email/language_preference) — see
context/decisions-log.md and app/schemas/admin.py's module docstring.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import require_roles
from app.core.security import hash_password
from app.models.enums import UserRole
from app.models.patient import Patient
from app.models.user import User
from app.schemas.admin import AdminUserCreate, AdminUserOut, AdminUserUpdate

router = APIRouter(prefix="/admin", tags=["admin"])


def _admin_user_out(db: Session, user: User) -> AdminUserOut:
    linked_summary: str | None = None
    diagnosis: str | None = None

    if user.role == UserRole.patient:
        patient = db.query(Patient).filter(Patient.user_id == user.id).first()
        if patient is not None:
            diagnosis = patient.diagnosis
            if patient.assigned_doctor_id is not None:
                doctor = db.get(User, patient.assigned_doctor_id)
                linked_summary = doctor.name if doctor else None
    elif user.role == UserRole.attendant:
        patient = db.query(Patient).filter(Patient.attendant_user_id == user.id).first()
        if patient is not None and patient.user_id is not None:
            patient_user = db.get(User, patient.user_id)
            linked_summary = patient_user.name if patient_user else patient.mr_number
    elif user.role == UserRole.doctor:
        count = db.query(Patient).filter(Patient.assigned_doctor_id == user.id).count()
        linked_summary = f"{count} patient{'s' if count != 1 else ''}"
    elif user.role == UserRole.admin:
        linked_summary = "System"

    return AdminUserOut(
        id=user.id,
        name=user.name,
        role=user.role.value,
        phone_or_email=user.phone_or_email,
        language_preference=user.language_preference.value,
        created_at=user.created_at,
        linked_summary=linked_summary,
        diagnosis=diagnosis,
    )


@router.get("/users", response_model=list[AdminUserOut])
def list_users(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin)),
) -> list[AdminUserOut]:
    users = db.query(User).order_by(User.id).all()
    return [_admin_user_out(db, u) for u in users]


@router.post("/users", response_model=AdminUserOut, status_code=status.HTTP_201_CREATED)
def create_user(
    payload: AdminUserCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin)),
) -> AdminUserOut:
    existing = db.query(User).filter(User.phone_or_email == payload.phone_or_email).first()
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this phone/email already exists",
        )

    user = User(
        name=payload.name,
        role=payload.role,
        phone_or_email=payload.phone_or_email,
        password_hash=hash_password(payload.password),
        language_preference=payload.language_preference,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _admin_user_out(db, user)


@router.patch("/users/{user_id}", response_model=AdminUserOut)
def update_user(
    user_id: int,
    payload: AdminUserUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin)),
) -> AdminUserOut:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    if payload.phone_or_email is not None and payload.phone_or_email != user.phone_or_email:
        conflict = db.query(User).filter(User.phone_or_email == payload.phone_or_email).first()
        if conflict is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="A user with this phone/email already exists",
            )
        user.phone_or_email = payload.phone_or_email

    if payload.name is not None:
        user.name = payload.name
    if payload.role is not None:
        user.role = payload.role
    if payload.language_preference is not None:
        user.language_preference = payload.language_preference

    db.commit()
    db.refresh(user)
    return _admin_user_out(db, user)
