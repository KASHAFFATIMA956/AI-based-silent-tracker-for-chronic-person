"""
risk_results — one-to-one with an entry — merged AI + rule-based output.

Schema doc 4.3. Kept separate from ai_results so the rule-based safety
engine can populate risk_results (source='rule') even when the Claude API
is unavailable — satisfies the required fallback behavior.
"""

from datetime import datetime

from sqlalchemy import Enum as PgEnum
from sqlalchemy import ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base
from app.models.enums import RiskLevel, RiskSource


class RiskResult(Base):
    __tablename__ = "risk_results"

    id: Mapped[int] = mapped_column(primary_key=True)

    entry_id: Mapped[int] = mapped_column(
        ForeignKey("entries.id"), nullable=False, unique=True
    )

    risk_level: Mapped[RiskLevel] = mapped_column(
        PgEnum(RiskLevel, name="risk_level"), nullable=False
    )
    # e.g. "A meaningful change", "Please seek care now".
    risk_title: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Plain-language explanation shown to the patient.
    risk_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Clinical rationale behind the level.
    reasoning: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Supports fallback logic and debugging.
    source: Mapped[RiskSource] = mapped_column(
        PgEnum(RiskSource, name="risk_source"), nullable=False
    )

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    def __repr__(self) -> str:
        return f"<RiskResult id={self.id} entry_id={self.entry_id} risk_level={self.risk_level}>"
