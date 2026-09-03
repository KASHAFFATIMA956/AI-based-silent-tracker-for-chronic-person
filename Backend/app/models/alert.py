"""
alerts — drives the doctor's Alerts Panel.

Schema doc 4.4.
"""

from datetime import datetime

from sqlalchemy import Boolean, Enum as PgEnum
from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base
from app.models.enums import RiskLevel


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[int] = mapped_column(primary_key=True)

    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id"), nullable=False
    )
    entry_id: Mapped[int | None] = mapped_column(
        ForeignKey("entries.id"), nullable=True
    )

    risk_level: Mapped[RiskLevel] = mapped_column(
        PgEnum(RiskLevel, name="risk_level"), nullable=False
    )
    # e.g. "Weight +2.4 kg in 5 days with falling sleep and sustained low energy."
    alert_text: Mapped[str] = mapped_column(Text, nullable=False)
    # e.g. "Baseline layer + weight red-flag rule".
    source_rule: Mapped[str | None] = mapped_column(String, nullable=True)

    # Marked true via the doctor notes/alert-review action.
    reviewed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    def __repr__(self) -> str:
        return f"<Alert id={self.id} patient_id={self.patient_id} risk_level={self.risk_level}>"
