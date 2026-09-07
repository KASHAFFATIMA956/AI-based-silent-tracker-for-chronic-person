"""
symptom_checklist_options — lookup table, varies by diagnosis.

Schema doc 4.2. Keyed by diagnosis (plain text) rather than fixed columns,
since post-surgical patients need a different checklist than heart-failure
patients — new conditions can be added without a schema change.
"""

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class SymptomChecklistOption(Base):
    __tablename__ = "symptom_checklist_options"

    id: Mapped[int] = mapped_column(primary_key=True)

    diagnosis: Mapped[str] = mapped_column(String, nullable=False)
    symptom_name: Mapped[str] = mapped_column(String, nullable=False)

    def __repr__(self) -> str:
        return f"<SymptomChecklistOption id={self.id} diagnosis={self.diagnosis!r} symptom_name={self.symptom_name!r}>"
