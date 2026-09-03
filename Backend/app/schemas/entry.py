"""
Schemas for POST /entries and GET /entries/{patient_id}/timeline.

Numeric bounds on the quick check-in fields (1-5 for
energy/mood/appetite/mobility, hours for sleep) reflect the scale
confirmed in context/decisions-log.md, sourced from
docs/RozNoor_Mobile_UI_Field_Requirements.docx (sliders with labeled
low/high ends, e.g. "Very poor -> Very good").

weight_value (kg) added 2026-08-24 — see context/decisions-log.md. Bounds
(0-300kg) are a generous sanity check, not a clinical range. It is not
gated to entry_type == quick the way the sliders are, but a weight-only
reading still counts as a valid "quick" entry on its own.
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.enums import EntryType, MedicineStatus


class EntryCreate(BaseModel):
    patient_id: int
    entry_type: EntryType
    # Defaults to submission time if omitted; callers may backdate for
    # demo/testing purposes.
    timestamp: datetime | None = None

    raw_transcript: str | None = None
    transcript_translation: str | None = None

    sleep_value: float | None = Field(default=None, ge=0, le=24)
    energy_value: float | None = Field(default=None, ge=1, le=5)
    mood_value: float | None = Field(default=None, ge=1, le=5)
    appetite_value: float | None = Field(default=None, ge=1, le=5)
    mobility_value: float | None = Field(default=None, ge=1, le=5)
    # Kilograms. Not a 1-5 slider like the other quick fields, but still
    # counts toward "quick entry needs at least one value" below — a
    # weight-only morning weigh-in is a legitimate quick entry on its own.
    weight_value: float | None = Field(default=None, ge=0, le=300)

    medicine_status: MedicineStatus
    symptom_ids: list[int] = []

    @model_validator(mode="after")
    def _check_entry_type_fields(self):
        if self.entry_type == EntryType.voice:
            if not self.raw_transcript or not self.raw_transcript.strip():
                raise ValueError("raw_transcript is required for a voice entry")
        else:  # quick
            quick_values = [
                self.sleep_value,
                self.energy_value,
                self.mood_value,
                self.appetite_value,
                self.mobility_value,
                self.weight_value,
            ]
            if all(v is None for v in quick_values):
                raise ValueError(
                    "at least one quick check-in value is required for a quick entry"
                )
        return self


class RiskResultOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    risk_level: str
    risk_title: str | None
    risk_message: str | None
    reasoning: str | None
    source: str


class EntryOut(BaseModel):
    id: int
    patient_id: int
    entry_type: str
    timestamp: datetime
    raw_transcript: str | None
    transcript_translation: str | None
    sleep_value: float | None
    energy_value: float | None
    mood_value: float | None
    appetite_value: float | None
    mobility_value: float | None
    weight_value: float | None
    medicine_status: str
    symptom_names: list[str] = []
    risk_result: RiskResultOut | None = None
    # True once POST /entries/{id}/audio has successfully attached a
    # recording. The server-side file path itself is never exposed to
    # clients — see app/routers/entries.py. Added 2026-08-25.
    has_audio: bool = False
    # Signal-processing output from app/services/audio_analysis.py, present
    # only once acoustic analysis has actually run for this entry (nullable
    # dict, not a fixed schema — see AiResult.acoustic_features for the key
    # names). Added 2026-08-25.
    acoustic_features: dict | None = None
