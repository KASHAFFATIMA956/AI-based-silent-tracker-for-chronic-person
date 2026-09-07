"""
ai_results — one-to-one with an entry — AI layer's extraction output.

Schema doc 4.3.
"""

from datetime import datetime

from sqlalchemy import ForeignKey
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class AiResult(Base):
    __tablename__ = "ai_results"

    id: Mapped[int] = mapped_column(primary_key=True)

    entry_id: Mapped[int] = mapped_column(
        ForeignKey("entries.id"), nullable=False, unique=True
    )

    # e.g. ["fatigue ↑", "onset: this morning"]
    extracted_symptom_tags: Mapped[dict | list | None] = mapped_column(
        JSONB, nullable=True
    )
    # Per-metric label/value/severity, e.g. sleep, weight, energy,
    # medicine adherence.
    deviation_deltas: Mapped[dict | list | None] = mapped_column(JSONB, nullable=True)

    # Deterministic signal-processing output from app/services/audio_analysis.py
    # (librosa — pure signal processing, NOT a machine-learning model; no
    # training data exists and none was fitted). Set by
    # POST /entries/{id}/audio for voice entries with an uploaded recording,
    # e.g. {"duration_sec": 12.4, "pause_ratio": 0.41, "num_pauses": 6,
    # "speaking_rate_segments_per_min": 14.2, "energy_rms_mean": 0.031,
    # "energy_rms_variance": 0.0002, "energy_cv": 0.14, "pitch_mean_hz":
    # 178.2, "pitch_variability_hz": 12.1, "possible_fatigue_or_breathlessness":
    # true}. Every threshold behind the derived boolean is a Claude Code
    # proposal, NOT clinician/training-data-validated — see
    # context/decisions-log.md. Added 2026-08-25.
    acoustic_features: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    def __repr__(self) -> str:
        return f"<AiResult id={self.id} entry_id={self.entry_id}>"
