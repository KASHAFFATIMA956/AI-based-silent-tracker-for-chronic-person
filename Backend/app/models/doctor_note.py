"""
doctor_notes — free-text clinical notes per patient.

Schema doc 4.4.
"""

from datetime import datetime

from sqlalchemy import ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class DoctorNote(Base):
    __tablename__ = "doctor_notes"

    id: Mapped[int] = mapped_column(primary_key=True)

    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id"), nullable=False
    )
    doctor_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)

    note_text: Mapped[str] = mapped_column(Text, nullable=False)

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    def __repr__(self) -> str:
        return f"<DoctorNote id={self.id} patient_id={self.patient_id} doctor_id={self.doctor_id}>"
