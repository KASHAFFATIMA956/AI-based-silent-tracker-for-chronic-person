"""
entries — every check-in, voice or quick.

Schema doc 4.2, plus weight_value added 2026-08-24 (see
context/decisions-log.md) — the schema doc's column list didn't include
it, but the project doc/prototype treat weight as a core heart-failure
safety signal (the "2kg in three days" red-flag threshold), so this was
a real gap rather than an intentional omission. Confirmed with the user
before adding.

sleep_value / energy_value / mood_value / appetite_value / mobility_value
are nullable and only populated for entry_type == "quick"; raw_transcript
and transcript_translation are nullable and only populated for
entry_type == "voice". weight_value is nullable and NOT tied to
entry_type — a morning weight reading (kg) can be logged alongside either
a voice or a quick entry (matches the prototype's "Morning weight logged"
adherence item, tracked independently of the check-in method).
"""

from datetime import datetime

from sqlalchemy import Enum as PgEnum
from sqlalchemy import ForeignKey, Numeric, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base
from app.models.enums import EntryType, MedicineStatus


class Entry(Base):
    __tablename__ = "entries"

    id: Mapped[int] = mapped_column(primary_key=True)

    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id"), nullable=False
    )

    entry_type: Mapped[EntryType] = mapped_column(
        PgEnum(EntryType, name="entry_type"), nullable=False
    )

    # Used for timeline ordering and the doctor's "last entry" display.
    timestamp: Mapped[datetime] = mapped_column(nullable=False)

    raw_transcript: Mapped[str | None] = mapped_column(Text, nullable=True)
    transcript_translation: Mapped[str | None] = mapped_column(Text, nullable=True)

    sleep_value: Mapped[float | None] = mapped_column(Numeric, nullable=True)
    energy_value: Mapped[float | None] = mapped_column(Numeric, nullable=True)
    mood_value: Mapped[float | None] = mapped_column(Numeric, nullable=True)
    appetite_value: Mapped[float | None] = mapped_column(Numeric, nullable=True)
    mobility_value: Mapped[float | None] = mapped_column(Numeric, nullable=True)

    # Kilograms. Not gated to a particular entry_type — see module docstring.
    weight_value: Mapped[float | None] = mapped_column(Numeric, nullable=True)

    # Local-disk path to the uploaded raw audio recording (voice entries
    # only) — settings.audio_storage_path/<patient_id>/<file>, either a
    # relative path resolved against the backend process's own working
    # directory (local dev) or an absolute path inside a mounted Railway
    # Volume (production — see context/pre-deployment-checklist.md item
    # 7), never a URL. Nullable — set by
    # POST /entries/{id}/audio, a separate call made AFTER entry creation
    # (see app/routers/entries.py), never by POST /entries itself. Added
    # 2026-08-25 (acoustic-analysis pass) — local disk is a hackathon-scope
    # shortcut, not a production storage choice; see context/decisions-log.md.
    audio_file_path: Mapped[str | None] = mapped_column(Text, nullable=True)

    medicine_status: Mapped[MedicineStatus] = mapped_column(
        PgEnum(MedicineStatus, name="medicine_status"), nullable=False
    )

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    def __repr__(self) -> str:
        return f"<Entry id={self.id} patient_id={self.patient_id} type={self.entry_type}>"
