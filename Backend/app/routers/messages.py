"""
Direct messaging between a patient (or their attendant) and their assigned
doctor. Added 2026-09-07 — see context/decisions-log.md.

Same `/patients` prefix as app/routers/patients.py (api-contracts.md groups
this under "Patients", same URL shape as /notes), split into its own file
since it's a large enough standalone feature (a chat thread, not a single
read/write pair) to warrant its own module rather than growing
patients.py further.

RBAC: GET reuses get_authorized_patient (admin/assigned-doctor/self-patient/
linked-attendant — same rule as GET /entries/{patient_id}/timeline). POST
is narrower — see app.core.deps.is_authorized_to_send_message's own
docstring for why admin can read but not send.

No websocket infrastructure exists in this backend (REST-only), and none is
added here — the frontend polls this GET endpoint on an interval while its
message screen is open instead. Real-time push (websockets/SSE) is a
possible future upgrade, not built this pass — see context/decisions-log.md.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_authorized_patient, get_current_user, is_authorized_to_send_message
from app.models.message import Message
from app.models.patient import Patient
from app.models.user import User
from app.schemas.message import MessageCreate, MessageOut

router = APIRouter(prefix="/patients", tags=["messages"])


def _message_out(db: Session, message: Message) -> MessageOut:
    sender = db.get(User, message.sender_user_id)
    return MessageOut(
        id=message.id,
        patient_id=message.patient_id,
        sender_user_id=message.sender_user_id,
        sender_role=message.sender_role.value,
        sender_name=sender.name if sender else None,
        content=message.content,
        created_at=message.created_at,
        read_at=message.read_at,
    )


@router.post("/{patient_id}/messages", response_model=MessageOut, status_code=201)
def create_message(
    payload: MessageCreate,
    patient: Patient = Depends(get_authorized_patient),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MessageOut:
    sender_role = is_authorized_to_send_message(current_user, patient)
    if sender_role is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the patient, their attendant, or their assigned doctor may send messages",
        )
    message = Message(
        patient_id=patient.id,
        sender_user_id=current_user.id,
        sender_role=sender_role,
        content=payload.content,
    )
    db.add(message)
    db.commit()
    db.refresh(message)
    return _message_out(db, message)


@router.get("/{patient_id}/messages", response_model=list[MessageOut])
def list_messages(
    patient: Patient = Depends(get_authorized_patient),
    db: Session = Depends(get_db),
) -> list[MessageOut]:
    # Oldest-first — deliberately the opposite of every other list endpoint
    # in this app (timeline/notes/alerts are all newest-first), since a chat
    # thread reads naturally top-to-bottom chronologically. See module
    # docstring / context/decisions-log.md.
    messages = (
        db.query(Message)
        .filter(Message.patient_id == patient.id)
        .order_by(Message.created_at.asc())
        .all()
    )
    return [_message_out(db, m) for m in messages]
