"""
patients — one row per patient, linked to a user.

Schema doc 4.1.

Notes:
- user_id is nullable: an attendant-managed patient may not log in directly.
- assigned_doctor_id and attendant_user_id both point at users.id and are
  expected (not DB-enforced) to reference rows with role=doctor /
  role=attendant respectively — enforcing that would need a trigger or
  application-level check, deferred past this MVP pass.
- medication_info is a free-text field, per the schema doc's default
  option (see context/decisions-log.md for the "12th table" discussion).
"""

from datetime import datetime

from sqlalchemy import Enum as PgEnum
from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base
from app.models.enums import BaselineStage


class Patient(Base):
    __tablename__ = "patients"

    id: Mapped[int] = mapped_column(primary_key=True)

    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id"), nullable=True
    )
    attendant_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id"), nullable=True
    )

    age: Mapped[int | None] = mapped_column(Integer, nullable=True)
    mr_number: Mapped[str | None] = mapped_column(String, nullable=True)

    # Editable list, not a hardcoded enum — new conditions can be added
    # without a schema change (mirrors symptom_checklist_options.diagnosis).
    diagnosis: Mapped[str | None] = mapped_column(String, nullable=True)

    assigned_doctor_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id"), nullable=True
    )

    emergency_contact_name: Mapped[str | None] = mapped_column(String, nullable=True)
    emergency_contact_phone: Mapped[str | None] = mapped_column(String, nullable=True)

    medication_info: Mapped[str | None] = mapped_column(Text, nullable=True)

    baseline_stage: Mapped[BaselineStage] = mapped_column(
        PgEnum(BaselineStage, name="baseline_stage"),
        nullable=False,
        default=BaselineStage.cold_start,
    )
    # Days since first entry — drives baseline_stage.
    day_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    def __repr__(self) -> str:
        return f"<Patient id={self.id} mr_number={self.mr_number!r}>"
