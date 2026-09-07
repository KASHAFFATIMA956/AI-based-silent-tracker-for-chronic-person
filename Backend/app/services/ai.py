"""
Claude API integration — symptom extraction from voice transcripts, and
baseline-aware plain-language summary generation.

## Fallback contract — read this before touching this module

Every public function here is soft-fail: if the API key is missing, the
Claude API errors, times out, or returns something that doesn't parse,
the function returns None (never raises). Callers (app/routers/entries.py,
app/routers/patients.py) MUST treat None as "AI unavailable" and continue
with the rule engine alone — this satisfies the project doc's explicit
fallback requirement (section 6.3: "Rule-based fallback when AI or
internet is unavailable"; section 14: "AI supports interpretation and
summarization; it does not replace clinical rules"). The rule engine
(app.services.rules) never depends on anything in this module and always
runs first/regardless.

## What AI does and doesn't decide here

- extract_symptoms() turns a free-text/voice transcript into (a) which of
  the patient's diagnosis-specific checklist symptoms were actually
  described, and (b) other notable phrases. The caller folds (a) into the
  SAME symptom set the rule engine scores — including hard red-flags — so
  a patient saying "chest pain" via voice triggers the same safety rule
  as ticking the checkbox would, even though no AI-only path can ever
  raise or lower a risk level by itself. AI only ever feeds symptom
  *evidence* into the existing rule engine; it never assigns a risk level.
- generate_patient_summary() writes the plain-language paragraph for the
  Result screen / doctor "Generate AI Summary" button (project doc
  section 6.4, matches the UI-Inspo prototype's SUMMARY text). It is
  handed already-computed numbers (baseline bands, recent risk levels)
  and is explicitly instructed never to invent a number or state a
  diagnosis — see its system prompt.
- deviation_deltas (ai_results.deviation_deltas) are computed in plain
  Python from the same baseline data the rule engine uses, NOT phrased by
  Claude — deterministic and can't hallucinate a number. Only
  extracted_symptom_tags reflects Claude's actual free-text interpretation.

Model: claude-opus-5 (project default per Anthropic guidance — this app
doesn't have a reason to downgrade). Kept to a hard request timeout so a
slow/hanging API call can't stall POST /entries indefinitely.
"""

from __future__ import annotations

import logging

import anthropic
from pydantic import BaseModel

from app.core.config import settings
from app.models.baseline_history import BaselineHistory
from app.models.entry import Entry

logger = logging.getLogger(__name__)

MODEL = "claude-opus-5"
REQUEST_TIMEOUT_SECONDS = 20.0

_METRIC_LABELS = {
    "sleep": ("Sleep", "h"),
    "energy": ("Energy", "/5"),
    "mood": ("Mood", "/5"),
    "appetite": ("Appetite", "/5"),
    "mobility": ("Mobility", "/5"),
    "weight": ("Weight", "kg"),
}
_METRIC_COLUMNS = {
    "sleep": "sleep_value",
    "energy": "energy_value",
    "mood": "mood_value",
    "appetite": "appetite_value",
    "mobility": "mobility_value",
    "weight": "weight_value",
}


def _get_client() -> anthropic.Anthropic | None:
    if not settings.anthropic_api_key:
        return None
    try:
        return anthropic.Anthropic(
            api_key=settings.anthropic_api_key,
            timeout=REQUEST_TIMEOUT_SECONDS,
            max_retries=1,
        )
    except Exception:  # noqa: BLE001 - client construction should never crash a caller
        logger.exception("Failed to construct Anthropic client")
        return None


# ---------------------------------------------------------------------------
# Symptom extraction (voice entries)
# ---------------------------------------------------------------------------


class _ExtractionSchema(BaseModel):
    matched_symptoms: list[str]
    free_tags: list[str]


class ExtractionResult(BaseModel):
    # Subset of checklist_names that Claude judged were actually described
    # in the transcript. Filtered against checklist_names again by the
    # caller-facing function below — never trust an out-of-list name.
    matched_symptoms: list[str]
    # Short notable phrases that aren't on the checklist, e.g.
    # "onset: this morning", "fatigue up" — stored for context, not scored.
    free_tags: list[str]


def extract_symptoms(
    raw_transcript: str, diagnosis: str, checklist_names: list[str]
) -> ExtractionResult | None:
    """
    Interpret a free-text/voice transcript (often Roman Urdu or mixed
    Roman Urdu/English) into structured symptom signals.

    Returns None on: no API key configured, empty transcript, any Claude
    API error/timeout, or a response that fails schema validation. Never
    raises.
    """
    client = _get_client()
    if client is None or not raw_transcript or not raw_transcript.strip():
        return None

    checklist_text = (
        ", ".join(checklist_names) if checklist_names else "(no checklist defined for this diagnosis)"
    )
    system = (
        "You are the symptom-extraction layer of RozNoor, a health-monitoring app "
        "for chronic-condition patients. Read a patient or attendant's spoken "
        "daily check-in and identify which symptoms from a FIXED clinical "
        "checklist were actually described. Only include a checklist symptom if "
        "it is clearly stated or clearly implied by the transcript — never guess "
        "or infer beyond what was actually said, and never include a symptom "
        "that is not in the provided checklist. You do not diagnose, assess "
        "severity, or decide a risk level — a separate deterministic rule engine "
        "does that from the symptoms you identify."
    )
    prompt = (
        f"Diagnosis: {diagnosis}\n"
        f"Checklist symptoms to check for: {checklist_text}\n\n"
        f'Transcript: "{raw_transcript}"\n\n'
        "Return matched_symptoms as the exact checklist strings that apply "
        "(empty list if none apply). Return free_tags as short phrases for "
        "anything notable in the transcript that is NOT on the checklist "
        '(e.g. "onset: this morning", "fatigue up") — empty list if nothing '
        "notable beyond the checklist matches."
    )

    try:
        response = client.messages.parse(
            model=MODEL,
            max_tokens=1024,
            output_config={"effort": "low"},  # classification-shaped task
            system=system,
            messages=[{"role": "user", "content": prompt}],
            output_format=_ExtractionSchema,
        )
        parsed = response.parsed_output
    except Exception:  # noqa: BLE001 - any failure here means "fall back to rules"
        logger.warning("AI symptom extraction failed; falling back to rule-only", exc_info=True)
        return None

    # Never trust a name Claude invented outside the given checklist.
    matched = [s for s in parsed.matched_symptoms if s in checklist_names]
    return ExtractionResult(matched_symptoms=matched, free_tags=parsed.free_tags)


def compute_deviation_deltas(
    entry: Entry, prior_baseline_rows: dict[str, BaselineHistory]
) -> dict:
    """
    Plain-Python (no AI) per-metric deviation summary for ai_results.
    deviation_deltas — e.g. {"sleep": {"label": "Sleep", "value": "5.0h vs
    6.2-7.6h", "severity": "medium"}}. Deterministic on purpose: these are
    real numbers, not something to let a language model phrase and risk
    getting wrong.
    """
    deltas: dict[str, dict] = {}
    for metric, column in _METRIC_COLUMNS.items():
        value = getattr(entry, column)
        band = prior_baseline_rows.get(metric)
        if value is None or band is None:
            continue
        value = float(value)
        band_min, band_max = float(band.baseline_min), float(band.baseline_max)
        label, unit = _METRIC_LABELS[metric]

        if band_min <= value <= band_max:
            severity = "none"
        else:
            gap = (band_min - value) if value < band_min else (value - band_max)
            band_width = max(band_max - band_min, 0.1)
            severity = "high" if gap >= band_width else "medium"

        deltas[metric] = {
            "label": label,
            "value": f"{value:g}{unit} vs {band_min:g}-{band_max:g}{unit}",
            "severity": severity,
        }
    return deltas


# ---------------------------------------------------------------------------
# Patient summary ("Generate AI Summary" / Result screen)
# ---------------------------------------------------------------------------

_SUMMARY_SYSTEM = (
    "You are RozNoor's clinician-facing summary layer. Write ONE short "
    "plain-language paragraph (120-180 words) describing this patient's "
    "recent pattern, grounded ONLY in the numeric data and stated risk "
    "levels given to you below — never invent a number, date, or symptom "
    "that isn't in the data. Never state or imply a medical diagnosis. If "
    "the data shows a risk escalation, make clear that the escalation was "
    "produced by the rule and baseline layers, not by this summary — you "
    "are interpreting and condensing already-computed data for a "
    "clinician's review, not deciding risk yourself. If a voice entry "
    "includes a signal-processing acoustic estimate (pause ratio, energy "
    "variability, a possible fatigue/breathlessness flag), you may "
    "mention it, but ALWAYS describe it as a deterministic signal-"
    "processing estimate from the recording — never as an AI judgment, a "
    "diagnosis, or a confirmed clinical finding. Write for a doctor "
    "who has 30 seconds to read this before seeing the patient."
)


def _format_entries_for_prompt(
    entries: list[Entry],
    baseline_rows: dict[str, BaselineHistory],
    acoustic_by_entry: dict[int, dict] | None = None,
) -> str:
    acoustic_by_entry = acoustic_by_entry or {}
    lines = []
    for e in entries:
        parts = [f"{e.timestamp.date()} ({e.entry_type.value})"]
        for metric, column in _METRIC_COLUMNS.items():
            value = getattr(e, column)
            if value is not None:
                label, unit = _METRIC_LABELS[metric]
                parts.append(f"{label}={float(value):g}{unit}")
        parts.append(f"medicine={e.medicine_status.value}")
        if e.transcript_translation:
            parts.append(f'note="{e.transcript_translation}"')
        acoustic = acoustic_by_entry.get(e.id)
        if acoustic:
            parts.append(
                f"voice-recording signal-processing: pause_ratio={acoustic.get('pause_ratio')}, "
                f"energy_cv={acoustic.get('energy_cv')}, "
                f"possible_fatigue_or_breathlessness={acoustic.get('possible_fatigue_or_breathlessness')} "
                "(deterministic acoustic estimate, not clinically validated — cite it as a "
                "signal-processing observation only, never as a diagnosis)"
            )
        lines.append(" - " + ", ".join(parts))

    band_lines = [
        f" - {_METRIC_LABELS.get(metric, (metric, ''))[0]}: learned band "
        f"{float(row.baseline_min):g}-{float(row.baseline_max):g}"
        for metric, row in baseline_rows.items()
    ]

    return (
        "Learned personal baseline bands:\n"
        + ("\n".join(band_lines) if band_lines else " (none yet — still in cold start)")
        + "\n\nRecent entries (newest first):\n"
        + ("\n".join(lines) if lines else " (no entries yet)")
    )


def generate_patient_summary(
    patient_name: str,
    diagnosis: str | None,
    entries: list[Entry],
    baseline_rows: dict[str, BaselineHistory],
    acoustic_by_entry: dict[int, dict] | None = None,
) -> str | None:
    """
    Baseline-aware plain-language summary across a patient's recent
    entries. Returns None on any failure — caller must show a fallback
    message, not a 500.

    acoustic_by_entry: optional {entry_id: ai_results.acoustic_features}
    for voice entries with an uploaded recording (added 2026-08-25,
    acoustic-analysis pass — see app/services/audio_analysis.py). Purely
    additive prompt context; omitting it changes nothing about the
    existing summary behavior.
    """
    client = _get_client()
    if client is None:
        return None

    data_block = _format_entries_for_prompt(entries, baseline_rows, acoustic_by_entry)
    prompt = (
        f"Patient: {patient_name}. Diagnosis: {diagnosis or 'not recorded'}.\n\n"
        f"{data_block}\n\n"
        "Write the summary paragraph now."
    )

    try:
        response = client.messages.create(
            model=MODEL,
            max_tokens=600,
            output_config={"effort": "medium"},
            system=_SUMMARY_SYSTEM,
            messages=[{"role": "user", "content": prompt}],
        )
    except Exception:  # noqa: BLE001 - any failure here means "no summary available"
        logger.warning("AI summary generation failed", exc_info=True)
        return None

    text = next((block.text for block in response.content if block.type == "text"), None)
    return text.strip() if text else None
