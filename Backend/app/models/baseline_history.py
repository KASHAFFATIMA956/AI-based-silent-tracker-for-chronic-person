"""
baseline_history — rolling personal baseline per patient per metric.

Schema doc 4.3. One row per patient per metric (not one row per patient)
— each metric (sleep, weight, energy, ...) has its own learned band and
updates independently, per the baseline-stage progression (cold start ->
learning -> personalized).
"""

from datetime import datetime

from sqlalchemy import ForeignKey, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class BaselineHistory(Base):
    __tablename__ = "baseline_history"

    id: Mapped[int] = mapped_column(primary_key=True)

    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id"), nullable=False
    )

    # sleep / energy / weight / mobility / etc.
    metric: Mapped[str] = mapped_column(String, nullable=False)

    baseline_min: Mapped[float] = mapped_column(Numeric, nullable=False)
    baseline_max: Mapped[float] = mapped_column(Numeric, nullable=False)

    last_updated: Mapped[datetime] = mapped_column(
        server_default=func.now(), onupdate=func.now()
    )

    def __repr__(self) -> str:
        return f"<BaselineHistory patient_id={self.patient_id} metric={self.metric!r}>"
