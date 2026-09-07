"""
Shared enum types used across models.

Value spelling choices (documented in context/decisions-log.md):
- Role/stage/type/status enums use lowercase snake_case values, since the
  schema doc gives them as plain slashed options (e.g. "patient / attendant
  / doctor / admin") with no canonical casing specified.
- risk_level is the one exception: the schema doc and the UI prototype
  both consistently capitalize Green/Yellow/Orange/Red as the literal
  user-facing labels, so that exact casing is preserved here.
"""

import enum


class UserRole(str, enum.Enum):
    patient = "patient"
    attendant = "attendant"
    doctor = "doctor"
    admin = "admin"


class LanguagePreference(str, enum.Enum):
    english = "english"
    roman_urdu = "roman_urdu"


class BaselineStage(str, enum.Enum):
    cold_start = "cold_start"
    learning = "learning"
    personalized = "personalized"


class EntryType(str, enum.Enum):
    voice = "voice"
    quick = "quick"


class MedicineStatus(str, enum.Enum):
    taken = "taken"
    missed = "missed"


class RiskLevel(str, enum.Enum):
    Green = "Green"
    Yellow = "Yellow"
    Orange = "Orange"
    Red = "Red"


class RiskSource(str, enum.Enum):
    ai = "ai"
    rule = "rule"
    merged = "merged"


class MessageSenderRole(str, enum.Enum):
    """
    Who sent a messages row — deliberately narrower than UserRole (no
    `admin` value): the direct-messaging feature (added 2026-09-07) is
    scoped to a patient/attendant/doctor thread only, so there's no
    sensible sender_role for an admin to be recorded under even though
    admin can still read any thread (same always-allowed-to-read,
    narrower-to-write shape as doctor_notes' clinician-only write RBAC).
    See context/decisions-log.md.
    """

    patient = "patient"
    attendant = "attendant"
    doctor = "doctor"
