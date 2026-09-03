"""
Import every model here so app.core.database.Base.metadata is fully
populated for Alembic autogenerate and for Base.metadata.create_all().
"""

from app.models.ai_result import AiResult
from app.models.alert import Alert
from app.models.baseline_history import BaselineHistory
from app.models.doctor_note import DoctorNote
from app.models.entry import Entry
from app.models.entry_symptom import EntrySymptom
from app.models.patient import Patient
from app.models.risk_result import RiskResult
from app.models.symptom_checklist_option import SymptomChecklistOption
from app.models.user import User
from app.models.weekly_digest import WeeklyDigest

__all__ = [
    "User",
    "Patient",
    "Entry",
    "EntrySymptom",
    "SymptomChecklistOption",
    "AiResult",
    "RiskResult",
    "BaselineHistory",
    "Alert",
    "DoctorNote",
    "WeeklyDigest",
]
