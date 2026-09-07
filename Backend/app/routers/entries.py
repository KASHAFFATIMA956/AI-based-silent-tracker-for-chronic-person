"""
Check-in submission (POST /entries) and patient timeline
(GET /entries/{patient_id}/timeline).

POST /entries runs the full rule-based safety pipeline synchronously,
plus an optional AI-interpretation step for voice entries:
  1. insert the entry (+ entry_symptoms for any submitted checklist items)
  2. for a VOICE entry only: call Claude to extract which of the
     diagnosis's checklist symptoms the transcript actually describes.
     On success, those matches are folded into the SAME symptom set the
     rule engine scores (including hard red-flags — see app/services/ai.py)
     and an ai_results row is written. On ANY failure (no API key,
     timeout, error) this step is silently skipped — nothing here can
     block or fail the request.
  3. evaluate red-flag / baseline-deviation / adherence rules against the
     PRE-update baseline bands and recent history -> a risk_results row.
     source='merged' if step 2 actually ran and returned data this call,
     else 'rule' — the rule engine itself is always what decides the
     level; AI only ever supplies additional symptom evidence into it.
  4. create an alerts row if risk_level != Green (Alerts Panel shows
     "All yellow/orange/red alerts" per the project doc)
  5. fold the new entry into baseline_history / patient.day_count /
     patient.baseline_stage for future comparisons

See app/services/rules.py, app/services/baseline.py, and app/services/ai.py
for the actual logic, sourcing, and fallback contract.

POST /entries/{entry_id}/audio (added 2026-08-25, acoustic-analysis pass)
is a SEPARATE, additive endpoint, deliberately NOT merged into POST
/entries — the mobile app calls it right after a successful voice-entry
submission, uploading the raw recording captured during Voice Diary.
Keeping POST /entries pure-JSON (its existing, verified contract,
untouched) means a failure anywhere in audio capture/upload/analysis can
never affect entry submission or its rule-based risk_result — see
context/decisions-log.md for the full rationale. It re-runs
rules.evaluate_entry with the acoustic signal added and updates the
entry's existing risk_result/alert in place.

systolic_bp/diastolic_bp/blood_sugar_mg_dl (added 2026-09-07, see
context/decisions-log.md) are accepted by EntryCreate and persisted on
the entry exactly like weight_value, but are deliberately NOT passed into
rules_service.evaluate_entry() below — they play no part in
risk_level/alerts yet. Wiring them in is a separate future pass requiring
real clinical threshold review, same discipline as every other threshold
in app/services/rules.py.
"""

import os
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_authorized_patient, is_authorized_for_patient, require_roles
from app.models.ai_result import AiResult
from app.models.alert import Alert
from app.models.baseline_history import BaselineHistory
from app.models.entry import Entry
from app.models.entry_symptom import EntrySymptom
from app.models.enums import EntryType, RiskLevel, RiskSource, UserRole
from app.models.patient import Patient
from app.models.risk_result import RiskResult
from app.models.symptom_checklist_option import SymptomChecklistOption
from app.models.user import User
from app.schemas.entry import EntryCreate, EntryOut, RiskResultOut
from app.services import ai as ai_service
from app.services import audio_analysis as audio_analysis_service
from app.services import baseline as baseline_service
from app.services import rules as rules_service

router = APIRouter(tags=["entries"])

# Extensions accepted from the mobile recorder — kept permissive since the
# `record` Flutter package's default output format differs by platform
# (m4a/aac on Android, generally). librosa (via audioread/ffmpeg) can load
# any of these; the extension is only used for the stored filename.
_ALLOWED_AUDIO_EXTENSIONS = {".m4a", ".aac", ".wav", ".mp3", ".ogg", ".webm"}


def _build_entry_out(
    entry: Entry,
    symptom_names: list[str],
    risk: RiskResult | None,
    ai_result: AiResult | None = None,
) -> EntryOut:
    acoustic_features = ai_result.acoustic_features if ai_result else None
    return EntryOut(
        id=entry.id,
        patient_id=entry.patient_id,
        entry_type=entry.entry_type.value,
        timestamp=entry.timestamp,
        raw_transcript=entry.raw_transcript,
        transcript_translation=entry.transcript_translation,
        sleep_value=entry.sleep_value,
        energy_value=entry.energy_value,
        mood_value=entry.mood_value,
        appetite_value=entry.appetite_value,
        mobility_value=entry.mobility_value,
        weight_value=entry.weight_value,
        systolic_bp=entry.systolic_bp,
        diastolic_bp=entry.diastolic_bp,
        blood_sugar_mg_dl=entry.blood_sugar_mg_dl,
        medicine_status=entry.medicine_status.value,
        symptom_names=symptom_names,
        risk_result=(
            RiskResultOut(
                risk_level=risk.risk_level.value,
                risk_title=risk.risk_title,
                risk_message=risk.risk_message,
                reasoning=risk.reasoning,
                source=risk.source.value,
            )
            if risk
            else None
        ),
        has_audio=bool(entry.audio_file_path),
        acoustic_features=acoustic_features,
    )


@router.post("/entries", response_model=EntryOut, status_code=status.HTTP_201_CREATED)
def create_entry(
    payload: EntryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.patient, UserRole.attendant)),
) -> EntryOut:
    patient = db.get(Patient, payload.patient_id)
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")
    if not is_authorized_for_patient(current_user, patient):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to submit entries for this patient",
        )

    symptom_options: list[SymptomChecklistOption] = []
    if payload.symptom_ids:
        symptom_options = (
            db.query(SymptomChecklistOption)
            .filter(SymptomChecklistOption.id.in_(payload.symptom_ids))
            .all()
        )
        if len(symptom_options) != len(set(payload.symptom_ids)):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="One or more symptom_ids do not exist",
            )

    entry = Entry(
        patient_id=patient.id,
        entry_type=payload.entry_type,
        timestamp=payload.timestamp or datetime.now(timezone.utc),
        raw_transcript=payload.raw_transcript,
        transcript_translation=payload.transcript_translation,
        sleep_value=payload.sleep_value,
        energy_value=payload.energy_value,
        mood_value=payload.mood_value,
        appetite_value=payload.appetite_value,
        mobility_value=payload.mobility_value,
        weight_value=payload.weight_value,
        systolic_bp=payload.systolic_bp,
        diastolic_bp=payload.diastolic_bp,
        blood_sugar_mg_dl=payload.blood_sugar_mg_dl,
        medicine_status=payload.medicine_status,
    )
    db.add(entry)
    db.flush()  # assign entry.id

    for opt in symptom_options:
        db.add(EntrySymptom(entry_id=entry.id, symptom_id=opt.id))

    # Baseline bands as they stood BEFORE this entry — rules (and the AI
    # deviation summary below) must compare against the prior learned
    # band, not one this entry has already been folded into.
    prior_baseline_rows = {
        row.metric: row
        for row in db.query(BaselineHistory).filter(BaselineHistory.patient_id == patient.id)
    }

    symptom_names = {opt.symptom_name for opt in symptom_options}
    already_linked_ids = {opt.id for opt in symptom_options}

    # --- AI interpretation step (voice entries only) -----------------------
    ai_extraction = None
    if payload.entry_type == EntryType.voice:
        ruleset_key = rules_service.diagnosis_key(patient.diagnosis)
        search_term = rules_service.CHECKLIST_DIAGNOSIS_SEARCH_TERMS.get(ruleset_key)
        checklist_options = (
            db.query(SymptomChecklistOption)
            .filter(SymptomChecklistOption.diagnosis.ilike(f"%{search_term}%"))
            .all()
            if search_term
            else []
        )
        if checklist_options:
            ai_extraction = ai_service.extract_symptoms(
                raw_transcript=entry.raw_transcript,
                diagnosis=patient.diagnosis or "",
                checklist_names=[o.symptom_name for o in checklist_options],
            )

        if ai_extraction is not None:
            name_to_option = {o.symptom_name: o for o in checklist_options}
            for name in ai_extraction.matched_symptoms:
                symptom_names.add(name)
                opt = name_to_option.get(name)
                # Persist an AI-detected symptom the same way a manual
                # tick would be, unless it's already linked.
                if opt and opt.id not in already_linked_ids:
                    db.add(EntrySymptom(entry_id=entry.id, symptom_id=opt.id))
                    already_linked_ids.add(opt.id)

            db.add(
                AiResult(
                    entry_id=entry.id,
                    extracted_symptom_tags=list(ai_extraction.matched_symptoms)
                    + list(ai_extraction.free_tags),
                    deviation_deltas=ai_service.compute_deviation_deltas(
                        entry, prior_baseline_rows
                    ),
                )
            )

    evaluation = rules_service.evaluate_entry(db, patient, entry, symptom_names, prior_baseline_rows)

    # The rule engine always runs and always decides the level (per the
    # fallback requirement) — AI only ever contributed symptom evidence
    # into it. source reflects whether that evidence was actually used
    # this call, not whether AI "decided" anything.
    final_source = RiskSource.merged if ai_extraction is not None else evaluation.source

    risk_result = RiskResult(
        entry_id=entry.id,
        risk_level=evaluation.risk_level,
        risk_title=evaluation.risk_title,
        risk_message=evaluation.risk_message,
        reasoning=evaluation.reasoning,
        source=final_source,
    )
    db.add(risk_result)

    if evaluation.risk_level != RiskLevel.Green:
        db.add(
            Alert(
                patient_id=patient.id,
                entry_id=entry.id,
                risk_level=evaluation.risk_level,
                alert_text=evaluation.reasoning,
                source_rule="; ".join(evaluation.triggered_rules) or None,
                reviewed=False,
            )
        )

    # Fold this entry into the baseline for future comparisons — AFTER
    # rule evaluation, so this entry never deviates against itself.
    baseline_service.update_baseline_after_entry(db, patient)

    db.commit()
    db.refresh(entry)
    db.refresh(risk_result)

    return _build_entry_out(entry, sorted(symptom_names), risk_result)


@router.get("/entries/{patient_id}/timeline", response_model=list[EntryOut])
def get_timeline(
    patient: Patient = Depends(get_authorized_patient),
    db: Session = Depends(get_db),
) -> list[EntryOut]:
    entries = (
        db.query(Entry)
        .filter(Entry.patient_id == patient.id)
        .order_by(Entry.timestamp.desc())
        .all()
    )

    results: list[EntryOut] = []
    for entry in entries:
        symptom_names = sorted(
            name
            for (name,) in (
                db.query(SymptomChecklistOption.symptom_name)
                .join(EntrySymptom, EntrySymptom.symptom_id == SymptomChecklistOption.id)
                .filter(EntrySymptom.entry_id == entry.id)
            )
        )
        risk = db.query(RiskResult).filter(RiskResult.entry_id == entry.id).first()
        ai_result = db.query(AiResult).filter(AiResult.entry_id == entry.id).first()
        results.append(_build_entry_out(entry, symptom_names, risk, ai_result))

    return results


@router.post("/entries/{entry_id}/audio", response_model=EntryOut)
def upload_entry_audio(
    entry_id: int,
    audio_file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.patient, UserRole.attendant)),
) -> EntryOut:
    """
    Attach a raw audio recording to an already-created voice entry and run
    deterministic acoustic-signal analysis over it (app/services/
    audio_analysis.py — pure signal processing, no ML model). Called by
    the mobile app right after a successful POST /entries(entry_type=voice)
    — see this file's module docstring for why this is a separate call
    rather than merged into that endpoint.

    Soft-fail by design: if the file can't be saved or analyzed, the
    entry/risk_result already created by POST /entries are left exactly as
    they were (has_audio stays false) — this endpoint can add signal, but
    can never take any away or block the transcript-only path. Re-runs the
    rule engine with the acoustic signal folded in and updates the entry's
    existing risk_result/alert in place (does not create a second
    risk_result row).
    """
    entry = db.get(Entry, entry_id)
    if entry is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Entry not found")

    patient = db.get(Patient, entry.patient_id)
    if patient is None or not is_authorized_for_patient(current_user, patient):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to attach audio to this entry",
        )

    if entry.entry_type != EntryType.voice:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Audio can only be attached to a voice entry",
        )

    # --- Save to local disk, under settings.audio_storage_path — a plain
    # relative path in local dev, or a path inside a Railway Volume mount
    # in production (see context/pre-deployment-checklist.md item 7) so it
    # survives a redeploy. Still single-instance local-disk storage either
    # way, not S3/cloud storage — see context/decisions-log.md for why a
    # Volume was chosen over cloud storage here. ----------------------
    storage_dir = os.path.join(settings.audio_storage_path, str(patient.id))
    os.makedirs(storage_dir, exist_ok=True)

    original_ext = os.path.splitext(audio_file.filename or "")[1].lower()
    ext = original_ext if original_ext in _ALLOWED_AUDIO_EXTENSIONS else ".m4a"
    stored_filename = f"entry{entry.id}_{uuid.uuid4().hex[:8]}{ext}"
    stored_path = os.path.join(storage_dir, stored_filename)

    try:
        contents = audio_file.file.read()
        if not contents:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Uploaded audio file is empty"
            )
        with open(stored_path, "wb") as f:
            f.write(contents)
    except HTTPException:
        raise
    except Exception:  # noqa: BLE001 - disk write failure must not crash the request
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save audio file",
        )

    entry.audio_file_path = stored_path

    # --- Acoustic feature extraction (soft-fail — see audio_analysis.py) --
    features = audio_analysis_service.extract_acoustic_features(stored_path)

    ai_result = db.query(AiResult).filter(AiResult.entry_id == entry.id).first()
    if features is not None:
        if ai_result is None:
            ai_result = AiResult(entry_id=entry.id, acoustic_features=features.to_dict())
            db.add(ai_result)
        else:
            ai_result.acoustic_features = features.to_dict()

    db.commit()
    db.refresh(entry)

    # --- Re-evaluate risk with the acoustic signal folded in --------------
    # Current symptom set for this entry (manual + AI-detected, already
    # persisted as entry_symptoms rows by POST /entries).
    symptom_names = {
        name
        for (name,) in (
            db.query(SymptomChecklistOption.symptom_name)
            .join(EntrySymptom, EntrySymptom.symptom_id == SymptomChecklistOption.id)
            .filter(EntrySymptom.entry_id == entry.id)
        )
    }

    # Current baseline_history as the "prior" bands. Safe for the voice-
    # entry case this endpoint is scoped to: a voice entry carries no
    # quick check-in values (sleep/energy/mood/appetite/mobility/weight
    # are all null — see app/schemas/entry.py), so folding it into
    # baseline_history at POST /entries time was a no-op for every metric
    # these bands track, and re-fetching the CURRENT bands here is
    # equivalent to the bands as they stood before that entry (assuming no
    # other entry was submitted for this patient in between, a reasonable
    # hackathon-scope assumption since audio upload happens moments after
    # entry creation, not asynchronously later — flagged in
    # context/decisions-log.md).
    baseline_rows = {
        row.metric: row
        for row in db.query(BaselineHistory).filter(BaselineHistory.patient_id == patient.id)
    }

    existing_risk = db.query(RiskResult).filter(RiskResult.entry_id == entry.id).first()

    if features is not None:
        evaluation = rules_service.evaluate_entry(
            db,
            patient,
            entry,
            symptom_names,
            baseline_rows,
            acoustic_flag=features.possible_fatigue_or_breathlessness,
            acoustic_detail=(
                f"voice recording pause ratio {features.pause_ratio:.0%} with flat vocal "
                f"energy (cv={features.energy_cv:.2f}) — possible fatigue/breathlessness "
                "pattern, signal-processing estimate, not clinically validated"
                if features.possible_fatigue_or_breathlessness
                else None
            ),
        )
        # The rule engine is still the sole decision-maker; source becomes
        # 'merged' whenever either AI or acoustic evidence contributed —
        # preserves the existing 'merged' semantics (app/services/ai.py
        # docstring) rather than inventing a third source value.
        was_ai_merged = existing_risk is not None and existing_risk.source == RiskSource.merged
        final_source = (
            RiskSource.merged
            if (was_ai_merged or features.possible_fatigue_or_breathlessness)
            else evaluation.source
        )

        if existing_risk is not None:
            existing_risk.risk_level = evaluation.risk_level
            existing_risk.risk_title = evaluation.risk_title
            existing_risk.risk_message = evaluation.risk_message
            existing_risk.reasoning = evaluation.reasoning
            existing_risk.source = final_source
        else:
            existing_risk = RiskResult(
                entry_id=entry.id,
                risk_level=evaluation.risk_level,
                risk_title=evaluation.risk_title,
                risk_message=evaluation.risk_message,
                reasoning=evaluation.reasoning,
                source=final_source,
            )
            db.add(existing_risk)

        # Keep the Alerts Panel in sync: create an alert if this newly
        # non-Green result has none yet, or update the existing one's
        # text/level in place — never a second alert for the same entry.
        if evaluation.risk_level != RiskLevel.Green:
            existing_alert = db.query(Alert).filter(Alert.entry_id == entry.id).first()
            if existing_alert is None:
                db.add(
                    Alert(
                        patient_id=patient.id,
                        entry_id=entry.id,
                        risk_level=evaluation.risk_level,
                        alert_text=evaluation.reasoning,
                        source_rule="; ".join(evaluation.triggered_rules) or None,
                        reviewed=False,
                    )
                )
            else:
                existing_alert.risk_level = evaluation.risk_level
                existing_alert.alert_text = evaluation.reasoning
                existing_alert.source_rule = "; ".join(evaluation.triggered_rules) or None

        db.commit()
        db.refresh(entry)
        db.refresh(existing_risk)

    symptom_names_sorted = sorted(symptom_names)
    return _build_entry_out(entry, symptom_names_sorted, existing_risk, ai_result)
