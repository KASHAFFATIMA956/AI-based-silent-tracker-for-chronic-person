"""
weekly_digests — optional — or compute live from entries + ai_results.

Schema doc 4.4. Implemented as a stored table per the "storing avoids
recompute" side of the open item in the schema doc section 6; revisit if
live computation turns out to be simpler once the digest endpoint is built.
"""

from datetime import date, datetime

from sqlalchemy import Date, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class WeeklyDigest(Base):
    __tablename__ = "weekly_digests"

    id: Mapped[int] = mapped_column(primary_key=True)

    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id"), nullable=False
    )

    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)

    # Plain-language weekly pattern summary.
    summary_text: Mapped[str] = mapped_column(Text, nullable=False)

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    def __repr__(self) -> str:
        return f"<WeeklyDigest id={self.id} patient_id={self.patient_id} period_start={self.period_start}>"
