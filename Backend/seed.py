"""
Seed script — populates sample patients, doctors, entries, AI/risk
results, baseline history, alerts, and notes matching the names/data
visible in the UI-Inspo prototype (RozNoor.dc.html), so early testing
looks realistic.

Safe to re-run: it clears existing rows (in FK-safe order) before
inserting, so `python seed.py` always leaves the DB in the same known
state. This is a dev/demo seed only — not meant to run against a DB with
real user data.

Usage:
    python seed.py          # requires DATABASE_URL / .env already pointing
                             # at a Postgres instance with migrations applied
                             # (alembic upgrade head)

Every seeded user shares one demo password (SEED_PASSWORD below), real
bcrypt-hashed via app.core.security.hash_password — not a placeholder.
Fine for demo/dev data; never reuse this password scheme once real users
exist.

Assumptions made for data not specified in the docs (see
context/decisions-log.md for the full list):
- Quick check-in metrics (energy/mood/appetite/mobility) are seeded on a
  1-5 scale (1 = very low, 5 = very good) — confirmed by the user as
  locked, not just assumed; sleep_value is in hours, matching the
  baseline chart ranges shown in the prototype (4.5-8h).
- Post-surgical symptom checklist options are invented (the prototype
  only shows the heart-failure checklist in full); heart-failure options
  are taken verbatim from the prototype's symDefs.
- weight_value is in kilograms. Zubaida Bibi's five most recent entries
  trace 62.0 -> 62.0 -> 62.6 -> 63.2 -> 63.8 -> 64.4 kg, reproducing the
  "+2.4 kg / 5 days" figure already referenced in her alert/risk text
  (added 2026-08-24 alongside entries.weight_value — see
  context/decisions-log.md). Ghulam Rasool and Mukhtar Ali also carry
  stable weight trends (no false-positive red flag) as a contrast case.
  Naseem/Bashir/Farida have no weight_value seeded — the weight red-flag
  rule only applies to the heart_failure ruleset.
"""

from datetime import date, datetime, timedelta

from app.core.database import Base, SessionLocal, engine
from app.core.security import hash_password
import app.models  # noqa: F401 - populates Base.metadata
from app.models.ai_result import AiResult
from app.models.alert import Alert
from app.models.baseline_history import BaselineHistory
from app.models.doctor_note import DoctorNote
from app.models.entry import Entry
from app.models.entry_symptom import EntrySymptom
from app.models.enums import (
    BaselineStage,
    EntryType,
    LanguagePreference,
    MedicineStatus,
    RiskLevel,
    RiskSource,
    UserRole,
)
from app.models.patient import Patient
from app.models.risk_result import RiskResult
from app.models.symptom_checklist_option import SymptomChecklistOption
from app.models.user import User
from app.models.weekly_digest import WeeklyDigest

SEED_PASSWORD = "RozNoor@123"  # shared demo password for every seeded user
SEED_PASSWORD_HASH = hash_password(SEED_PASSWORD)

TODAY = datetime.combine(date.today(), datetime.min.time())


def dt(days_ago: int, hour: int, minute: int) -> datetime:
    return (TODAY - timedelta(days=days_ago)).replace(hour=hour, minute=minute)


def baseline_stage_for(day_count: int) -> BaselineStage:
    if day_count <= 7:
        return BaselineStage.cold_start
    if day_count <= 14:
        return BaselineStage.learning
    return BaselineStage.personalized


def clear_all(session):
    """Delete in FK-safe (child-first) order."""
    for model in [
        WeeklyDigest,
        DoctorNote,
        Alert,
        BaselineHistory,
        RiskResult,
        AiResult,
        EntrySymptom,
        Entry,
        SymptomChecklistOption,
        Patient,
        User,
    ]:
        session.query(model).delete()
    session.commit()


def run():
    Base.metadata.create_all(bind=engine)  # no-op once Alembic has run; safe fallback
    session = SessionLocal()
    try:
        clear_all(session)

        # ---------------------------------------------------------------
        # Users
        # ---------------------------------------------------------------
        dr_farooq = User(
            name="Dr. Ayesha Farooq",
            role=UserRole.doctor,
            phone_or_email="a.farooq@civilhosp.pk",
            password_hash=SEED_PASSWORD_HASH,
            language_preference=LanguagePreference.english,
        )
        dr_iqbal = User(
            name="Dr. Hamza Iqbal",
            role=UserRole.doctor,
            phone_or_email="h.iqbal@civilhosp.pk",
            password_hash=SEED_PASSWORD_HASH,
            language_preference=LanguagePreference.english,
        )
        admin_kamran = User(
            name="Sadia Kamran",
            role=UserRole.admin,
            phone_or_email="s.kamran@civilhosp.pk",
            password_hash=SEED_PASSWORD_HASH,
            language_preference=LanguagePreference.english,
        )
        imran_attendant = User(
            name="Imran Zubair",
            role=UserRole.attendant,
            phone_or_email="imran.z@roznoor.care",
            password_hash=SEED_PASSWORD_HASH,
            language_preference=LanguagePreference.roman_urdu,
        )

        patient_users = {
            "ghulam": User(
                name="Ghulam Rasool",
                role=UserRole.patient,
                phone_or_email="ghulam.rasool@roznoor.care",
                password_hash=SEED_PASSWORD_HASH,
                language_preference=LanguagePreference.roman_urdu,
            ),
            "zubaida": User(
                name="Zubaida Bibi",
                role=UserRole.patient,
                phone_or_email="zubaida.b@roznoor.care",
                password_hash=SEED_PASSWORD_HASH,
                language_preference=LanguagePreference.roman_urdu,
            ),
            "naseem": User(
                name="Naseem Akhtar",
                role=UserRole.patient,
                phone_or_email="naseem.a@roznoor.care",
                password_hash=SEED_PASSWORD_HASH,
                language_preference=LanguagePreference.roman_urdu,
            ),
            "bashir": User(
                name="Bashir Ahmed",
                role=UserRole.patient,
                phone_or_email="bashir.a@roznoor.care",
                password_hash=SEED_PASSWORD_HASH,
                language_preference=LanguagePreference.roman_urdu,
            ),
            "farida": User(
                name="Farida Yousuf",
                role=UserRole.patient,
                phone_or_email="farida.y@roznoor.care",
                password_hash=SEED_PASSWORD_HASH,
                language_preference=LanguagePreference.roman_urdu,
            ),
            "mukhtar": User(
                name="Mukhtar Ali",
                role=UserRole.patient,
                phone_or_email="mukhtar.a@roznoor.care",
                password_hash=SEED_PASSWORD_HASH,
                language_preference=LanguagePreference.roman_urdu,
            ),
        }

        session.add_all(
            [dr_farooq, dr_iqbal, admin_kamran, imran_attendant, *patient_users.values()]
        )
        session.flush()  # assign ids

        # ---------------------------------------------------------------
        # Symptom checklist options
        # ---------------------------------------------------------------
        hf_symptom_names = [
            "Breathlessness",
            "Ankle swelling",
            "Chest pain",
            "Dizziness",
            "Night cough",
            "Palpitations",
        ]
        ps_symptom_names = [
            "Wound redness",
            "Wound discharge",
            "Fever",
            "Incision pain",
            "Reduced mobility",
            "Swelling at site",
        ]
        hf_symptoms = {
            name: SymptomChecklistOption(diagnosis="Heart failure", symptom_name=name)
            for name in hf_symptom_names
        }
        ps_symptoms = {
            name: SymptomChecklistOption(diagnosis="Post-surgical", symptom_name=name)
            for name in ps_symptom_names
        }
        session.add_all([*hf_symptoms.values(), *ps_symptoms.values()])
        session.flush()

        # ---------------------------------------------------------------
        # Patients
        # ---------------------------------------------------------------
        p_ghulam = Patient(
            user_id=patient_users["ghulam"].id,
            attendant_user_id=None,
            age=71,
            mr_number="MR 40-1188",
            diagnosis="Heart failure",
            assigned_doctor_id=dr_farooq.id,
            emergency_contact_name="Rescue 1122",
            emergency_contact_phone="1122",
            medication_info="Furosemide 40mg - morning; Bisoprolol 2.5mg - morning; Ramipril 5mg - night",
            baseline_stage=baseline_stage_for(26),
            day_count=26,
        )
        p_zubaida = Patient(
            user_id=patient_users["zubaida"].id,
            attendant_user_id=imran_attendant.id,
            age=68,
            mr_number="MR 40-2291",
            diagnosis="Heart failure, post-discharge",
            assigned_doctor_id=dr_farooq.id,
            emergency_contact_name="Rescue 1122",
            emergency_contact_phone="1122",
            medication_info="Furosemide 40mg - morning; Bisoprolol 2.5mg - morning; Ramipril 5mg - night",
            baseline_stage=baseline_stage_for(19),
            day_count=19,
        )
        p_naseem = Patient(
            user_id=patient_users["naseem"].id,
            attendant_user_id=None,
            age=59,
            mr_number="MR 40-2010",
            diagnosis="Post-surgical",
            assigned_doctor_id=dr_iqbal.id,
            emergency_contact_name="Rescue 1122",
            emergency_contact_phone="1122",
            medication_info="Amoxicillin 500mg - three times daily; Paracetamol 500mg - as needed",
            baseline_stage=baseline_stage_for(12),
            day_count=12,
        )
        p_bashir = Patient(
            user_id=patient_users["bashir"].id,
            attendant_user_id=None,
            age=64,
            mr_number="MR 40-1974",
            diagnosis="Heart failure",
            assigned_doctor_id=dr_farooq.id,
            emergency_contact_name="Rescue 1122",
            emergency_contact_phone="1122",
            medication_info="Furosemide 40mg - morning; Ramipril 5mg - night",
            baseline_stage=baseline_stage_for(33),
            day_count=33,
        )
        p_farida = Patient(
            user_id=patient_users["farida"].id,
            attendant_user_id=None,
            age=55,
            mr_number="MR 40-2255",
            diagnosis="Post-surgical",
            assigned_doctor_id=dr_iqbal.id,
            emergency_contact_name="Rescue 1122",
            emergency_contact_phone="1122",
            medication_info="Amoxicillin 500mg - three times daily",
            baseline_stage=baseline_stage_for(9),
            day_count=9,
        )
        p_mukhtar = Patient(
            user_id=patient_users["mukhtar"].id,
            attendant_user_id=None,
            age=70,
            mr_number="MR 40-1902",
            diagnosis="Heart failure",
            assigned_doctor_id=dr_farooq.id,
            emergency_contact_name="Rescue 1122",
            emergency_contact_phone="1122",
            medication_info="Furosemide 40mg - morning; Bisoprolol 2.5mg - morning",
            baseline_stage=baseline_stage_for(41),
            day_count=41,
        )

        session.add_all([p_ghulam, p_zubaida, p_naseem, p_bashir, p_farida, p_mukhtar])
        session.flush()

        # ---------------------------------------------------------------
        # Entries + AI results + risk results (+ symptoms, alerts)
        # ---------------------------------------------------------------
        def add_entry(
            patient,
            entry_type,
            days_ago,
            hour,
            minute,
            medicine_status,
            *,
            raw_transcript=None,
            transcript_translation=None,
            sleep=None,
            energy=None,
            mood=None,
            appetite=None,
            mobility=None,
            weight=None,
            symptoms=(),
            symptom_tags=None,
            deviation_deltas=None,
            risk_level=None,
            risk_title=None,
            risk_message=None,
            reasoning=None,
            risk_source=RiskSource.rule,
            alert_text=None,
            source_rule=None,
            alert_reviewed=False,
        ):
            entry = Entry(
                patient_id=patient.id,
                entry_type=entry_type,
                timestamp=dt(days_ago, hour, minute),
                raw_transcript=raw_transcript,
                transcript_translation=transcript_translation,
                sleep_value=sleep,
                energy_value=energy,
                mood_value=mood,
                appetite_value=appetite,
                mobility_value=mobility,
                weight_value=weight,
                medicine_status=medicine_status,
            )
            session.add(entry)
            session.flush()

            for symptom in symptoms:
                session.add(EntrySymptom(entry_id=entry.id, symptom_id=symptom.id))

            if symptom_tags is not None or deviation_deltas is not None:
                session.add(
                    AiResult(
                        entry_id=entry.id,
                        extracted_symptom_tags=symptom_tags,
                        deviation_deltas=deviation_deltas,
                    )
                )

            if risk_level is not None:
                session.add(
                    RiskResult(
                        entry_id=entry.id,
                        risk_level=risk_level,
                        risk_title=risk_title,
                        risk_message=risk_message,
                        reasoning=reasoning,
                        source=risk_source,
                    )
                )

            if alert_text is not None:
                session.add(
                    Alert(
                        patient_id=patient.id,
                        entry_id=entry.id,
                        risk_level=risk_level,
                        alert_text=alert_text,
                        source_rule=source_rule,
                        reviewed=alert_reviewed,
                    )
                )

            return entry

        # --- Ghulam Rasool (Red today - chest pain at rest) ---
        add_entry(
            p_ghulam,
            EntryType.voice,
            0,
            7,
            2,
            MedicineStatus.taken,
            raw_transcript="Seene mein jakadan mehsoos ho rahi hai, aaram karte waqt bhi.",
            transcript_translation="Feeling chest tightness, even while resting.",
            weight=75.0,
            symptoms=[hf_symptoms["Chest pain"]],
            symptom_tags=["chest tightness ↑", "onset: at rest"],
            risk_level=RiskLevel.Red,
            risk_title="Please seek care now",
            risk_message="A critical concern was detected. Contact emergency services or your medical provider immediately.",
            reasoning="Chest pain in a post-discharge heart-failure patient is a clinician-set red flag. This does not wait for a baseline comparison.",
            risk_source=RiskSource.rule,
            alert_text="Reported chest tightness at rest. Rule-based escalation, attendant notified.",
            source_rule="Red-flag rule · heart failure v4",
            alert_reviewed=False,
        )
        add_entry(
            p_ghulam,
            EntryType.quick,
            4,
            8,
            10,
            MedicineStatus.taken,
            sleep=6.4,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            weight=74.8,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="All tracked metrics within learned personal band.",
            risk_source=RiskSource.rule,
        )
        add_entry(
            p_ghulam,
            EntryType.quick,
            9,
            8,
            5,
            MedicineStatus.taken,
            sleep=6.6,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            weight=74.5,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="All tracked metrics within learned personal band.",
            risk_source=RiskSource.rule,
        )

        # --- Zubaida Bibi (Orange - weight/sleep/energy trend) ---
        add_entry(
            p_zubaida,
            EntryType.voice,
            0,
            9,
            14,
            MedicineStatus.taken,
            raw_transcript="Aaj subah se sans pholna aur pair mein sujan hai, thakan bhi zyada hai.",
            transcript_translation="Breathlessness since this morning, ankle swelling, and more fatigue than usual.",
            weight=64.4,
            symptoms=[hf_symptoms["Breathlessness"], hf_symptoms["Ankle swelling"]],
            symptom_tags=["breathlessness ↑", "ankle swelling ↑", "fatigue ↑"],
            deviation_deltas={
                "weight": {"label": "Weight", "delta": "+2.4 kg / 5 days", "severity": "high"},
                "sleep": {"label": "Sleep", "delta": "-1.4h vs last week", "severity": "medium"},
                "energy": {"label": "Energy", "delta": "-2 steps vs baseline", "severity": "medium"},
            },
            risk_level=RiskLevel.Orange,
            risk_title="A meaningful change",
            risk_message="There is a meaningful change in your recent pattern. Consider contacting your doctor.",
            reasoning="Weight +2.4 kg in 5 days with falling sleep and sustained low energy, outside personal baseline band.",
            risk_source=RiskSource.merged,
            alert_text="Weight +2.4 kg in 5 days with falling sleep and sustained low energy.",
            source_rule="Baseline layer + weight red-flag rule",
            alert_reviewed=False,
        )
        add_entry(
            p_zubaida,
            EntryType.quick,
            2,
            9,
            31,
            MedicineStatus.taken,
            sleep=5.1,
            energy=2,
            mood=3,
            appetite=3,
            mobility=3,
            weight=63.8,
            risk_level=RiskLevel.Yellow,
            risk_title="Some changes are below your usual pattern",
            risk_message="Monitor the next few days.",
            reasoning="Sleep and energy both a step below usual. No new symptoms reported.",
            risk_source=RiskSource.rule,
        )
        add_entry(
            p_zubaida,
            EntryType.voice,
            3,
            8,
            40,
            MedicineStatus.taken,
            raw_transcript="Neend poori nahi hui, subah thora chakkar bhi aaya.",
            transcript_translation="Didn't get enough sleep, felt slightly dizzy in the morning.",
            weight=63.2,
            symptoms=[hf_symptoms["Dizziness"]],
            symptom_tags=["poor sleep", "dizziness ↑ (brief)"],
            risk_level=RiskLevel.Yellow,
            risk_title="Some changes are below your usual pattern",
            risk_message="Monitor the next few days.",
            reasoning="Poor sleep with brief morning dizziness; below personal band, not yet a red flag.",
            risk_source=RiskSource.rule,
        )
        add_entry(
            p_zubaida,
            EntryType.quick,
            4,
            9,
            0,
            MedicineStatus.taken,
            sleep=5.5,
            energy=2,
            mood=3,
            appetite=3,
            mobility=3,
            weight=62.6,
            risk_level=RiskLevel.Yellow,
            risk_title="Some changes are below your usual pattern",
            risk_message="Monitor the next few days.",
            reasoning="Sleep and energy below personal band.",
            risk_source=RiskSource.rule,
        )
        add_entry(
            p_zubaida,
            EntryType.quick,
            5,
            8,
            50,
            MedicineStatus.taken,
            sleep=6.5,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            weight=62.0,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="Mild sluggishness, otherwise within band.",
            risk_source=RiskSource.rule,
        )
        add_entry(
            p_zubaida,
            EntryType.quick,
            7,
            19,
            30,
            MedicineStatus.missed,
            sleep=6.8,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            weight=62.0,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="One missed evening dose logged by attendant.",
            risk_source=RiskSource.rule,
        )

        # --- Naseem Akhtar (Orange - missed doses + rising fatigue) ---
        add_entry(
            p_naseem,
            EntryType.quick,
            0,
            8,
            30,
            MedicineStatus.missed,
            sleep=6.0,
            energy=2,
            mood=3,
            appetite=3,
            mobility=3,
            symptom_tags=["fatigue ↑"],
            risk_level=RiskLevel.Orange,
            risk_title="A meaningful change",
            risk_message="There is a meaningful change in your recent pattern. Consider contacting your doctor.",
            reasoning="3 missed doses in the last week with rising fatigue.",
            risk_source=RiskSource.merged,
            alert_text="3 missed doses this week, fatigue trending upward.",
            source_rule="Medication adherence rule + baseline layer",
            alert_reviewed=False,
        )
        add_entry(
            p_naseem,
            EntryType.quick,
            2,
            8,
            15,
            MedicineStatus.missed,
            sleep=6.2,
            energy=2,
            mood=3,
            appetite=3,
            mobility=3,
            risk_level=RiskLevel.Yellow,
            risk_title="Some changes are below your usual pattern",
            risk_message="Monitor the next few days.",
            reasoning="Second missed dose this week.",
            risk_source=RiskSource.rule,
        )
        add_entry(
            p_naseem,
            EntryType.quick,
            5,
            8,
            0,
            MedicineStatus.missed,
            sleep=6.5,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="Single missed dose, otherwise within band.",
            risk_source=RiskSource.rule,
        )

        # --- Bashir Ahmed (Yellow - sleep below band, 2 nights) ---
        add_entry(
            p_bashir,
            EntryType.quick,
            0,
            8,
            20,
            MedicineStatus.taken,
            sleep=5.0,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            risk_level=RiskLevel.Yellow,
            risk_title="Some changes are below your usual pattern",
            risk_message="Monitor the next few days.",
            reasoning="Sleep below band for the 2nd consecutive night.",
            risk_source=RiskSource.rule,
            alert_text="Sleep below personal band, 2 nights in a row.",
            source_rule="Baseline layer · sleep deviation",
            alert_reviewed=False,
        )
        add_entry(
            p_bashir,
            EntryType.quick,
            1,
            8,
            25,
            MedicineStatus.taken,
            sleep=5.2,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            risk_level=RiskLevel.Yellow,
            risk_title="Some changes are below your usual pattern",
            risk_message="Monitor the next few days.",
            reasoning="Sleep below personal band.",
            risk_source=RiskSource.rule,
        )
        add_entry(
            p_bashir,
            EntryType.quick,
            4,
            8,
            15,
            MedicineStatus.taken,
            sleep=7.0,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="Within personal band.",
            risk_source=RiskSource.rule,
        )

        # --- Farida Yousuf (Yellow - appetite down) ---
        add_entry(
            p_farida,
            EntryType.quick,
            0,
            8,
            55,
            MedicineStatus.taken,
            sleep=6.8,
            energy=3,
            mood=3,
            appetite=2,
            mobility=3,
            risk_level=RiskLevel.Yellow,
            risk_title="Some changes are below your usual pattern",
            risk_message="Monitor the next few days.",
            reasoning="Appetite two steps below personal baseline.",
            risk_source=RiskSource.rule,
            alert_text="Appetite -2 steps vs personal baseline.",
            source_rule="Baseline layer · appetite deviation",
            alert_reviewed=False,
        )
        add_entry(
            p_farida,
            EntryType.quick,
            3,
            8,
            45,
            MedicineStatus.taken,
            sleep=6.9,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="Within personal band.",
            risk_source=RiskSource.rule,
        )

        # --- Mukhtar Ali (Green - stable) ---
        add_entry(
            p_mukhtar,
            EntryType.quick,
            0,
            9,
            5,
            MedicineStatus.taken,
            sleep=7.0,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            weight=70.1,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="Within personal band.",
            risk_source=RiskSource.rule,
        )
        add_entry(
            p_mukhtar,
            EntryType.quick,
            3,
            9,
            0,
            MedicineStatus.taken,
            sleep=7.1,
            energy=3,
            mood=3,
            appetite=3,
            mobility=3,
            weight=70.0,
            risk_level=RiskLevel.Green,
            risk_title="Stable",
            risk_message="Your recent entry appears close to your usual pattern.",
            reasoning="Within personal band.",
            risk_source=RiskSource.rule,
        )

        # ---------------------------------------------------------------
        # Baseline history (personal learned ranges)
        # ---------------------------------------------------------------
        session.add_all(
            [
                BaselineHistory(patient_id=p_zubaida.id, metric="sleep", baseline_min=6.2, baseline_max=7.6),
                BaselineHistory(patient_id=p_zubaida.id, metric="weight", baseline_min=61.4, baseline_max=62.6),
                BaselineHistory(patient_id=p_zubaida.id, metric="energy", baseline_min=3, baseline_max=4),
                BaselineHistory(patient_id=p_ghulam.id, metric="sleep", baseline_min=6.0, baseline_max=7.5),
                BaselineHistory(patient_id=p_ghulam.id, metric="weight", baseline_min=74.0, baseline_max=75.5),
                BaselineHistory(patient_id=p_naseem.id, metric="energy", baseline_min=3, baseline_max=4),
                BaselineHistory(patient_id=p_bashir.id, metric="sleep", baseline_min=6.3, baseline_max=7.4),
                BaselineHistory(patient_id=p_farida.id, metric="appetite", baseline_min=3, baseline_max=4),
                BaselineHistory(patient_id=p_mukhtar.id, metric="sleep", baseline_min=6.5, baseline_max=7.8),
                BaselineHistory(patient_id=p_mukhtar.id, metric="weight", baseline_min=69.5, baseline_max=70.5),
            ]
        )

        # ---------------------------------------------------------------
        # Doctor notes
        # ---------------------------------------------------------------
        session.add_all(
            [
                DoctorNote(
                    patient_id=p_zubaida.id,
                    doctor_id=dr_farooq.id,
                    note_text="Advised low-salt diet, daily weight log, and follow-up in 3 days if no improvement.",
                ),
                DoctorNote(
                    patient_id=p_ghulam.id,
                    doctor_id=dr_farooq.id,
                    note_text="Chest tightness at rest - escalated per red-flag rule. Attendant notified, awaiting ER update.",
                ),
                DoctorNote(
                    patient_id=p_naseem.id,
                    doctor_id=dr_iqbal.id,
                    note_text="Reinforced medication schedule with attendant; reviewing adherence at next check-in.",
                ),
            ]
        )

        # ---------------------------------------------------------------
        # Weekly digest (example, per doc section 9 "silent pattern" quote)
        # ---------------------------------------------------------------
        session.add(
            WeeklyDigest(
                patient_id=p_zubaida.id,
                period_start=(TODAY - timedelta(days=6)).date(),
                period_end=TODAY.date(),
                summary_text="Your sleep has been lower than usual for 4 days, and your fatigue reports have increased during the same period.",
            )
        )

        session.commit()

        print("Seed complete:")
        print(f"  users: {session.query(User).count()}")
        print(f"  patients: {session.query(Patient).count()}")
        print(f"  symptom_checklist_options: {session.query(SymptomChecklistOption).count()}")
        print(f"  entries: {session.query(Entry).count()}")
        print(f"  entry_symptoms: {session.query(EntrySymptom).count()}")
        print(f"  ai_results: {session.query(AiResult).count()}")
        print(f"  risk_results: {session.query(RiskResult).count()}")
        print(f"  baseline_history: {session.query(BaselineHistory).count()}")
        print(f"  alerts: {session.query(Alert).count()}")
        print(f"  doctor_notes: {session.query(DoctorNote).count()}")
        print(f"  weekly_digests: {session.query(WeeklyDigest).count()}")
        print()
        print(f"Demo login for every seeded user: password = '{SEED_PASSWORD}'")
        print("e.g. POST /auth/login {\"phone_or_email\": \"zubaida.b@roznoor.care\", \"password\": \"" + SEED_PASSWORD + "\"}")
    finally:
        session.close()


if __name__ == "__main__":
    run()
