"""
Auth endpoints: login (issues a JWT) and /me (returns the caller's own
identity — also a convenient way to sanity-check a token).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from sqlalchemy import or_

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.security import create_access_token, verify_password
from app.models.patient import Patient
from app.models.user import User
from app.schemas.auth import CurrentUserResponse, LoginRequest, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    user = (
        db.query(User)
        .filter(User.phone_or_email == payload.phone_or_email)
        .first()
    )
    if user is None or not verify_password(payload.password, user.password_hash):
        # Same message for "no such user" and "wrong password" — avoids
        # leaking which one it was.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect phone/email or password",
        )

    token = create_access_token(user_id=user.id, role=user.role.value)
    return TokenResponse(
        access_token=token,
        expires_in=settings.access_token_expire_minutes * 60,
        user_id=user.id,
        role=user.role.value,
        name=user.name,
    )


@router.get("/me", response_model=CurrentUserResponse)
def me(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CurrentUserResponse:
    # patient_id lookup: only patient/attendant roles can ever be linked to
    # a Patient row this way (doctor/admin stay None). One query, cheap at
    # hackathon data volumes — see schemas/auth.py docstring for why this
    # exists.
    patient_id = None
    if current_user.role.value in ("patient", "attendant"):
        patient = (
            db.query(Patient)
            .filter(
                or_(
                    Patient.user_id == current_user.id,
                    Patient.attendant_user_id == current_user.id,
                )
            )
            .first()
        )
        patient_id = patient.id if patient else None

    return CurrentUserResponse(
        id=current_user.id,
        name=current_user.name,
        role=current_user.role.value,
        phone_or_email=current_user.phone_or_email,
        language_preference=current_user.language_preference.value,
        patient_id=patient_id,
    )
