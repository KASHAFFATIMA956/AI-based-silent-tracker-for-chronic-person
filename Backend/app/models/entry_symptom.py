"""
entry_symptoms — many-to-many: symptoms selected per entry.

Schema doc 4.2.
"""

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class EntrySymptom(Base):
    __tablename__ = "entry_symptoms"

    id: Mapped[int] = mapped_column(primary_key=True)

    entry_id: Mapped[int] = mapped_column(ForeignKey("entries.id"), nullable=False)
    symptom_id: Mapped[int] = mapped_column(
        ForeignKey("symptom_checklist_options.id"), nullable=False
    )

    def __repr__(self) -> str:
        return f"<EntrySymptom entry_id={self.entry_id} symptom_id={self.symptom_id}>"
