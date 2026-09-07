"""
messages — direct-messaging thread between a patient (or their attendant)
and their assigned doctor. One row per message; a patient's full thread is
every messages row with that patient_id, ordered oldest-first (see
app/routers/messages.py — the one deliberate ordering exception in this
app; every other list endpoint, e.g. GET /entries/{id}/timeline, is
newest-first, but a chat thread reads naturally top-to-bottom
chronologically).

Added 2026-09-07 (direct-messaging pass) — see context/decisions-log.md.
No existing table was touched or restructured to add this feature.

read_at exists per the task's own schema spec but nothing sets it this
pass — no PATCH/mark-as-read endpoint, no read-receipts UI (explicitly out
of scope). It's always NULL for now; wiring it up is a future task.
"""

from datetime import datetime

from sqlalchemy import Enum as PgEnum
from sqlalchemy import ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base
from app.models.enums import MessageSenderRole


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(primary_key=True)

    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), nullable=False)
    # The user who actually sent this message — a patient, their attendant,
    # or their assigned doctor (never admin — see MessageSenderRole).
    sender_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    sender_role: Mapped[MessageSenderRole] = mapped_column(
        PgEnum(MessageSenderRole, name="message_sender_role"), nullable=False
    )

    content: Mapped[str] = mapped_column(Text, nullable=False)

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    # Never set by any endpoint this pass — see module docstring.
    read_at: Mapped[datetime | None] = mapped_column(nullable=True)

    def __repr__(self) -> str:
        return f"<Message id={self.id} patient_id={self.patient_id} sender_user_id={self.sender_user_id}>"
