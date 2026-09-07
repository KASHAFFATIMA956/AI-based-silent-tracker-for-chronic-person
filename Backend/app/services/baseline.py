"""
Baseline tracking — pure Python, no AI.

Implements the three-stage baseline lifecycle from
docs/RozNoor_Final_Project_Document.docx section 8:
  - cold_start   (day 1-7):   "collect daily data and calculate initial
                                statistical ranges"
  - learning     (day 8-14):  "continue baseline learning and accumulate
                                history"
  - personalized (day 15+):   "analyze deviations using the patient's own
                                history and retrain periodically"

The project doc names these three stages and their day ranges but gives
no literal formula for what a "baseline range" actually *is* at each
stage. This module's exact math — raw min/max for cold_start/learning,
mean +/- 1 standard deviation once personalized — is Claude Code's
proposal, not a clinician-confirmed formula. Flagged in
context/decisions-log.md as needing review.

Tracked metrics: sleep, energy, mood, appetite, mobility, weight (from
entries.*_value — weight_value added 2026-08-24, see
context/decisions-log.md). Note that for weight this band is tracked for
charting/trend purposes only — the safety-relevant direction (a RISE) is
handled by app.services.rules's dedicated hard_red_weight_gain check, not
by comparing against this band's lower bound (which is what
app.services.rules.evaluate_entry's generic deviation scoring does for
the other metrics).
"""

from statistics import mean, pstdev

from sqlalchemy.orm import Session

from app.models.baseline_history import BaselineHistory
from app.models.entry import Entry
from app.models.enums import BaselineStage
from app.models.patient import Patient

# metric name (as stored in baseline_history.metric) -> entries column name
METRIC_COLUMNS = {
    "sleep": "sleep_value",
    "energy": "energy_value",
    "mood": "mood_value",
    "appetite": "appetite_value",
    "mobility": "mobility_value",
    "weight": "weight_value",
}


def stage_for_day_count(day_count: int) -> BaselineStage:
    if day_count <= 7:
        return BaselineStage.cold_start
    if day_count <= 14:
        return BaselineStage.learning
    return BaselineStage.personalized


def update_baseline_after_entry(db: Session, patient: Patient) -> None:
    """
    Recomputes patient.day_count / patient.baseline_stage and every
    tracked metric's baseline_history row, from the full set of that
    patient's entries to date (including the entry just inserted into
    the session — call this AFTER inserting the new Entry).

    This does a full recompute from all entries each time rather than an
    incremental update — simpler and correct at hackathon data volumes;
    revisit if this ever needs to scale past a few thousand entries per
    patient.
    """
    entries = (
        db.query(Entry)
        .filter(Entry.patient_id == patient.id)
        .order_by(Entry.timestamp.asc())
        .all()
    )
    if not entries:
        return

    first_ts = entries[0].timestamp
    last_ts = entries[-1].timestamp
    day_count = (last_ts.date() - first_ts.date()).days + 1
    patient.day_count = day_count
    patient.baseline_stage = stage_for_day_count(day_count)

    existing_rows = {
        row.metric: row
        for row in db.query(BaselineHistory).filter(
            BaselineHistory.patient_id == patient.id
        )
    }

    for metric, column in METRIC_COLUMNS.items():
        values = [
            float(getattr(e, column))
            for e in entries
            if getattr(e, column) is not None
        ]
        if not values:
            continue

        if patient.baseline_stage == BaselineStage.personalized and len(values) >= 2:
            m = mean(values)
            sd = pstdev(values) or 0.5  # avoid a zero-width band on constant history
            lo, hi = m - sd, m + sd
        else:
            lo, hi = min(values), max(values)
            if lo == hi:
                # A zero-width band would flag every future value as a
                # deviation — pad it slightly.
                lo, hi = lo - 0.5, hi + 0.5

        row = existing_rows.get(metric)
        if row is None:
            db.add(
                BaselineHistory(
                    patient_id=patient.id,
                    metric=metric,
                    baseline_min=lo,
                    baseline_max=hi,
                )
            )
        else:
            row.baseline_min = lo
            row.baseline_max = hi
