"""
Rule-based safety engine — disease-specific red-flag rules + baseline
deviation + symptom/medicine-adherence scoring, producing a
Green/Yellow/Orange/Red decision with source='rule'.

This is the documented safety fallback and must work with zero AI
involvement — see docs/RozNoor_Final_Project_Document.docx section 6.3
("Rule-based fallback when AI or internet is unavailable") and section 14
("Never replace clinician-reviewed red-flag rules... AI supports
interpretation; it does not replace clinical rules").

## Where these numbers come from

The project doc speaks only in general terms about red flags
("disease-specific red-flag rules", "noticeable pattern change") with two
exceptions pulled from the UI-Inspo prototype (RozNoor.dc.html), which
carries real clinician-authored copy:
  - Chest pain in a post-discharge heart-failure patient is an instant
    red flag, independent of baseline ("This does not wait for a
    baseline comparison" — prototype line ~1307).
  - "sudden weight gain over 2kg in three days" is called a
    "clinician-set heart-failure threshold" (prototype SUMMARY text).
    Implemented as of 2026-08-24 (entries.weight_value added — see
    context/decisions-log.md) as HEART_FAILURE_RULES["hard_red_weight_gain"],
    checked in `_weight_gain_red_flag`. Kept per-ruleset (not a module-level
    constant) since only heart_failure has a clinician-set weight
    threshold; other diagnoses simply omit the key.
  - The prototype's own interactive demo scoring function (riskFor())
    gives real relative weights for two more heart-failure symptoms:
    breathlessness (3 points) and ankle swelling (2 points), and real
    score bands (>=7 Yellow, >=10 Orange, >=14 or chest-pain Red) that
    this module's thresholds are rescaled from.

Everything else below — post-surgical rules entirely, the remaining
heart-failure symptom weights, baseline-deviation point values, the
missed-dose streak rule, and the final score thresholds — is Claude
Code's proposal, not a clinician-confirmed value. All flagged again in
context/decisions-log.md as needing your (or an actual clinician's)
review before this is trusted for anything beyond a hackathon demo.

Per docs section 6.4/8 ("Red-flag rule sets... versioned and cannot be
edited by the AI layer — only by a named clinician reviewer"), the real
product intends these rule sets to be a versioned, clinician-editable
store. This module is the MVP stand-in for that — plain Python constants,
not yet a database-backed/versioned table.

## Acoustic signal (added 2026-08-25, acoustic-analysis pass)

`evaluate_entry()`'s optional `acoustic_flag` parameter carries the
`possible_fatigue_or_breathlessness` boolean computed by
app/services/audio_analysis.py (pure signal processing over the uploaded
Voice Diary recording — see that module's docstring for the full
threshold rationale). ACOUSTIC_FATIGUE_BREATHLESSNESS_POINTS below is a
Claude Code proposal with even less grounding than the rest of this
file's proposed weights — no clinician review, no training data, not
diagnosis-specific (applied uniformly across rulesets, since long
pauses + flat vocal energy aren't a heart-failure- or post-surgical-
specific pattern the way symptom checklists are). Deliberately kept a
Layer-B score contributor only, never a hard Layer-A red flag — this
signal has no evidence base remotely comparable to the doc-sourced hard
flags (chest pain, weight gain), so it must never be able to send
someone to Red on its own. It is also evaluated as a SEPARATE call
(`POST /entries/{id}/audio`, after the entry already exists with a
rule-only or merged result from the transcript) — see
app/routers/entries.py — not part of the original POST /entries
evaluation, since audio upload happens after entry creation.
"""

from dataclasses import dataclass, field
from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.models.baseline_history import BaselineHistory
from app.models.entry import Entry
from app.models.enums import MedicineStatus, RiskLevel, RiskSource
from app.models.patient import Patient


@dataclass
class RiskEvaluation:
    risk_level: RiskLevel
    risk_title: str
    risk_message: str
    reasoning: str
    source: RiskSource = RiskSource.rule
    triggered_rules: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Per-diagnosis rule sets.
# ---------------------------------------------------------------------------

HEART_FAILURE_RULES = {
    # Doc-sourced (see module docstring): independent of baseline.
    "hard_red_symptoms": {"Chest pain"},
    # Doc-sourced (prototype SUMMARY text): "clinician-set heart-failure
    # threshold" of 2.0kg gained within a 3-day window. Only heart_failure
    # carries this key — post_surgical/generic have no weight red-flag.
    "hard_red_weight_gain": {"kg": 2.0, "days": 3},
    # Doc-sourced: Breathlessness=3, Ankle swelling=2 (prototype riskFor()).
    # Dizziness/Palpitations/Night cough weights are Claude Code's
    # extrapolation — NEEDS CLINICIAN REVIEW.
    "weighted_symptoms": {
        "Breathlessness": 3,
        "Ankle swelling": 2,
        "Dizziness": 2,
        "Palpitations": 2,
        "Night cough": 1,
    },
}

POST_SURGICAL_RULES = {
    # Entirely proposed — the prototype only shows a version tag
    # ("Post-surgical · v2 · reviewed 18 Jul"), no rule text.
    # NEEDS CLINICIAN REVIEW.
    "hard_red_symptoms": {"Wound discharge"},
    "weighted_symptoms": {
        "Fever": 3,
        "Wound redness": 2,
        "Incision pain": 1,
        "Reduced mobility": 1,
        "Swelling at site": 1,
    },
}

GENERIC_RULES = {
    # No clinician-reviewed rule set exists yet for this diagnosis —
    # mirrors the prototype's "COPD · draft" state (no rules written).
    # Baseline-deviation and medicine-adherence scoring still apply;
    # there are just no diagnosis-specific symptom weights or hard flags.
    "hard_red_symptoms": set(),
    "weighted_symptoms": {},
}

_RULESETS = {
    "heart_failure": HEART_FAILURE_RULES,
    "post_surgical": POST_SURGICAL_RULES,
    "generic": GENERIC_RULES,
}

# Proposed score thresholds — rescaled from the prototype's own
# load>=7/10/14 bands to this module's point values. NEEDS REVIEW.
SCORE_YELLOW_THRESHOLD = 5
SCORE_ORANGE_THRESHOLD = 8

# "Repeated missed medication" (doc section 9 example) — proposed as 3+
# missed doses within the trailing 7 days. NEEDS REVIEW.
MISSED_DOSE_WINDOW_DAYS = 7
MISSED_DOSE_STREAK_THRESHOLD = 3
MISSED_DOSE_STREAK_POINTS = 3
MISSED_DOSE_SINGLE_POINTS = 1

# Baseline deviation points — proposed. A metric more than
# MODERATE_DEVIATION_MARGIN units below its learned band counts as
# "moderate", otherwise "mild".
MILD_DEVIATION_POINTS = 1
MODERATE_DEVIATION_POINTS = 2
MODERATE_DEVIATION_MARGIN = 1.0

# Acoustic signal contribution — NEEDS REVIEW, no clinician/training-data
# basis (see module docstring). Same order of magnitude as the other
# proposed symptom weights, deliberately not enough on its own to cross
# SCORE_ORANGE_THRESHOLD from a clean baseline.
ACOUSTIC_FATIGUE_BREATHLESSNESS_POINTS = 2

# Consecutive-entries-below-band streak worth calling out on its own.
# Doc section 9 example: "sleep... lower than usual for 4 days"; the
# prototype's own Yellow example: "shorter than your learned band for
# two nights". Proposed streak length: 2. NEEDS REVIEW.
BELOW_BAND_STREAK_THRESHOLD = 2
BELOW_BAND_STREAK_POINTS = 1
BELOW_BAND_STREAK_LOOKBACK = 7  # how many recent entries to scan for a streak

_METRIC_COLUMNS = {
    "sleep": "sleep_value",
    "energy": "energy_value",
    "mood": "mood_value",
    "appetite": "appetite_value",
    "mobility": "mobility_value",
}
# Deliberately excludes weight: this dict drives Layer B's generic
# "value < baseline_min is bad" deviation/streak scoring, which is the
# wrong direction for weight in heart failure (a RISE is the danger
# signal, not a dip — that's what the dedicated
# hard_red_weight_gain / _weight_gain_red_flag check below is for).
# weight still gets its own baseline_history band via
# app.services.baseline.METRIC_COLUMNS, for charting/trend purposes.


def diagnosis_key(diagnosis: str | None) -> str:
    """
    diagnosis is free text (schema doc: "editable list, not a hardcoded
    enum"), so this is a best-effort case-insensitive substring match,
    not an exact lookup. "Heart failure, post-discharge" and "Heart
    failure" both match "heart_failure"; anything unrecognized falls
    back to the diagnosis-agnostic generic ruleset.
    """
    text = (diagnosis or "").lower()
    if "heart failure" in text:
        return "heart_failure"
    if "post-surgical" in text or "post surgical" in text:
        return "post_surgical"
    return "generic"


# Substring to ILIKE-match against symptom_checklist_options.diagnosis for
# a given ruleset key — that column is also free text (seeded as exactly
# "Heart failure" / "Post-surgical"), so this mirrors diagnosis_key()'s
# normalization rather than assuming an exact string match. No entry for
# "generic" — there's no defined checklist for an unrecognized diagnosis.
# Used by app.services.ai to scope which checklist symptoms Claude is
# allowed to match a transcript against.
CHECKLIST_DIAGNOSIS_SEARCH_TERMS = {
    "heart_failure": "heart failure",
    "post_surgical": "post-surgical",
}


def evaluate_entry(
    db: Session,
    patient: Patient,
    entry: Entry,
    symptom_names: set[str],
    prior_baseline_rows: dict[str, BaselineHistory],
    acoustic_flag: bool = False,
    acoustic_detail: str | None = None,
) -> RiskEvaluation:
    """
    Evaluate one new entry against diagnosis-specific red flags, the
    patient's PRE-this-entry baseline bands, and recent history.

    prior_baseline_rows: {metric: BaselineHistory} as they stood BEFORE
    this entry was folded into the baseline — the caller must fetch
    these before calling app.services.baseline.update_baseline_after_entry,
    otherwise a deviation would be compared against a band that already
    includes the very value being evaluated.

    acoustic_flag / acoustic_detail: the optional signal-processing
    `possible_fatigue_or_breathlessness` result from
    app.services.audio_analysis (see that module's and this module's own
    docstring for the threshold rationale/caveats). Layer-B-only
    contribution — see ACOUSTIC_FATIGUE_BREATHLESSNESS_POINTS above.
    """
    ruleset_key = diagnosis_key(patient.diagnosis)
    ruleset = _RULESETS[ruleset_key]
    triggered: list[str] = []

    # ---- Layer A: hard red-flag rules (bypass baseline entirely) ---------
    hard_hits = symptom_names & ruleset["hard_red_symptoms"]

    weight_cfg = ruleset.get("hard_red_weight_gain")
    weight_gain_hit, weight_gain_detail = (
        _weight_gain_red_flag(db, patient, entry, weight_cfg["kg"], weight_cfg["days"])
        if weight_cfg
        else (False, "")
    )

    if hard_hits or weight_gain_hit:
        reason_parts: list[str] = []
        rule_names: list[str] = []
        if hard_hits:
            hit_list = ", ".join(sorted(hard_hits))
            reason_parts.append(f"{hit_list} is a clinician-set red flag for this diagnosis")
            rule_names.append(f"{ruleset_key} red-flag: {hit_list}")
        if weight_gain_hit:
            reason_parts.append(weight_gain_detail)
            rule_names.append(f"{ruleset_key} red-flag: {weight_gain_detail}")

        return RiskEvaluation(
            risk_level=RiskLevel.Red,
            risk_title="Please seek care now",
            risk_message=(
                "A critical concern was detected. Contact emergency services "
                "or your medical provider immediately."
            ),
            reasoning=(
                "; ".join(reason_parts).capitalize()
                + ". This does not wait for a baseline comparison."
            ),
            triggered_rules=rule_names,
        )

    # ---- Layer B: weighted composite score --------------------------------
    score = 0
    reasons: list[str] = []

    for name in sorted(symptom_names):
        weight = ruleset["weighted_symptoms"].get(name)
        if weight:
            score += weight
            triggered.append(f"symptom:{name}(+{weight})")
            reasons.append(name.lower())

    deviated_metrics: list[str] = []
    for metric, column in _METRIC_COLUMNS.items():
        value = getattr(entry, column)
        band = prior_baseline_rows.get(metric)
        if value is None or band is None:
            continue
        value = float(value)
        band_min = float(band.baseline_min)
        if value < band_min:
            gap = band_min - value
            points = (
                MODERATE_DEVIATION_POINTS
                if gap >= MODERATE_DEVIATION_MARGIN
                else MILD_DEVIATION_POINTS
            )
            score += points
            deviated_metrics.append(metric)
            triggered.append(f"baseline:{metric}(+{points})")

    if deviated_metrics:
        reasons.append(f"{', '.join(deviated_metrics)} below your learned personal band")

    for metric, streak in _below_band_streaks(db, patient, prior_baseline_rows).items():
        if streak >= BELOW_BAND_STREAK_THRESHOLD:
            score += BELOW_BAND_STREAK_POINTS
            triggered.append(f"streak:{metric}({streak} entries)")
            reasons.append(f"{metric} below band for {streak} consecutive entries")

    missed_count = _missed_dose_count(db, patient, reference_time=entry.timestamp)
    if missed_count >= MISSED_DOSE_STREAK_THRESHOLD:
        score += MISSED_DOSE_STREAK_POINTS
        triggered.append(
            f"medicine:missed_streak({missed_count} in {MISSED_DOSE_WINDOW_DAYS}d)"
        )
        reasons.append(f"{missed_count} missed doses in the last {MISSED_DOSE_WINDOW_DAYS} days")
    elif entry.medicine_status == MedicineStatus.missed:
        score += MISSED_DOSE_SINGLE_POINTS
        triggered.append("medicine:missed_single")

    if acoustic_flag:
        score += ACOUSTIC_FATIGUE_BREATHLESSNESS_POINTS
        triggered.append(f"acoustic:fatigue_breathlessness(+{ACOUSTIC_FATIGUE_BREATHLESSNESS_POINTS})")
        reasons.append(
            acoustic_detail
            or "voice recording shows long pauses and unusually flat vocal energy "
            "(possible fatigue/breathlessness pattern, signal-processing estimate)"
        )

    if score >= SCORE_ORANGE_THRESHOLD:
        level = RiskLevel.Orange
        title = "A meaningful change"
        message = "There is a meaningful change in your recent pattern. Consider contacting your doctor."
    elif score >= SCORE_YELLOW_THRESHOLD:
        level = RiskLevel.Yellow
        title = "Some changes are below your usual pattern"
        message = "Monitor the next few days."
    else:
        level = RiskLevel.Green
        title = "Stable"
        message = "Your recent entry appears close to your usual pattern."

    reasoning = (
        ("; ".join(reasons)).capitalize() + "."
        if reasons
        else "All tracked signals are within your learned personal band."
    )

    return RiskEvaluation(
        risk_level=level,
        risk_title=title,
        risk_message=message,
        reasoning=reasoning,
        triggered_rules=triggered,
    )


def _below_band_streaks(
    db: Session, patient: Patient, baseline_rows: dict[str, BaselineHistory]
) -> dict[str, int]:
    """
    For each metric with a baseline band, count how many of the most
    recent consecutive entries (newest first) fall below baseline_min.
    Stops at the first entry that doesn't, or after
    BELOW_BAND_STREAK_LOOKBACK entries. Assumes entries are submitted in
    roughly chronological order (a materially backdated entry could skew
    this — acceptable for hackathon scope).
    """
    recent = (
        db.query(Entry)
        .filter(Entry.patient_id == patient.id)
        .order_by(Entry.timestamp.desc())
        .limit(BELOW_BAND_STREAK_LOOKBACK)
        .all()
    )

    streaks: dict[str, int] = {}
    for metric, column in _METRIC_COLUMNS.items():
        band = baseline_rows.get(metric)
        if band is None:
            continue
        band_min = float(band.baseline_min)
        streak = 0
        for e in recent:
            value = getattr(e, column)
            if value is None:
                break
            if float(value) < band_min:
                streak += 1
            else:
                break
        if streak:
            streaks[metric] = streak
    return streaks


def _weight_gain_red_flag(
    db: Session, patient: Patient, entry: Entry, threshold_kg: float, window_days: int
) -> tuple[bool, str]:
    """
    Doc-sourced red flag: a rise of >= threshold_kg (2.0) within any
    window_days-day (3) window ending at this entry's own weight reading.

    Compares against the LOWEST weight_value logged by this patient in
    the window strictly before this entry (not just the earliest one),
    so an upward spike is caught regardless of whether weight dipped
    first — a single earliest-vs-latest comparison could miss that.
    """
    if entry.weight_value is None:
        return False, ""

    window_start = entry.timestamp - timedelta(days=window_days)
    prior_rows = (
        db.query(Entry)
        .filter(
            Entry.patient_id == patient.id,
            Entry.id != entry.id,
            Entry.weight_value.isnot(None),
            Entry.timestamp >= window_start,
            Entry.timestamp < entry.timestamp,
        )
        .all()
    )
    if not prior_rows:
        return False, ""

    min_prior = min(float(r.weight_value) for r in prior_rows)
    current = float(entry.weight_value)
    gain = current - min_prior
    if gain >= threshold_kg:
        return (
            True,
            f"weight +{gain:.1f}kg within {window_days} days "
            f"({min_prior:.1f}kg -> {current:.1f}kg)",
        )
    return False, ""


def _missed_dose_count(db: Session, patient: Patient, reference_time: datetime) -> int:
    """
    Missed doses in the MISSED_DOSE_WINDOW_DAYS trailing `reference_time`
    (the entry's own timestamp, not wall-clock time — keeps this correct
    for backdated/demo data the way seed.py generates it).
    """
    cutoff = reference_time - timedelta(days=MISSED_DOSE_WINDOW_DAYS)
    return (
        db.query(Entry)
        .filter(
            Entry.patient_id == patient.id,
            Entry.medicine_status == MedicineStatus.missed,
            Entry.timestamp >= cutoff,
            Entry.timestamp <= reference_time,
        )
        .count()
    )
