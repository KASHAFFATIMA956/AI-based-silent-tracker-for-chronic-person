"""
Deterministic acoustic-signal analysis for Voice Diary recordings — pure
signal processing, NOT a machine-learning model. No training data exists
for this project and building/fitting one is out of scope for this
timeline (see context/decisions-log.md, 2026-08-25 acoustic-analysis
pass) — every feature here is a directly-computed signal-processing
statistic (energy, silence, pitch), and every derived "possible X" flag is
a hand-picked threshold on those statistics, in the same rule-based spirit
as app/services/rules.py.

## Implementation: numpy + system ffmpeg, NOT librosa — a mid-build pivot, explained

This was originally built on librosa (the task's own suggested default).
It was rewritten to a hand-rolled numpy implementation (decoding via a
`ffmpeg` subprocess, framing/RMS/silence-detection/pitch-via-autocorrelation
done by hand) after `pip install librosa` repeatedly failed to complete in
this sandbox's actual network conditions — measured at times under 10KB/s
to PyPI, with librosa's numba/llvmlite/scipy/scikit-learn dependency chain
alone totaling 100+MB of wheels (llvmlite's wheel is ~60MB by itself).
Two separate install attempts (one bounded at 600s, one left to run
unbounded in the background) both failed to finish within a reasonable
session timeframe — this is a real, demonstrated infrastructure
constraint, not a hypothetical one, and exactly the kind of situation the
task's own "propose an equivalent lightweight library if librosa is a
poor fit" instruction anticipated. `numpy` alone installs in seconds (it
has no heavy compiled transitive dependencies beyond itself); `ffmpeg` is
already present system-wide on this machine and handles decoding
arbitrary input formats (m4a/aac from the mobile recorder, wav, mp3, ogg,
webm) exactly the way librosa would have delegated to it via `audioread`
under the hood anyway. Net effect: fewer, lighter dependencies for a
hackathon deploy target, at the cost of hand-rolled (rather than
research-library-grade) pitch tracking — see the pitch section below for
that specific trade-off, called out honestly.

**Runtime requirement**: the `ffmpeg` binary must be on PATH. If it isn't,
`extract_acoustic_features()` returns None (soft-fail), same as any other
failure — see the fallback contract below.

## Fallback contract — same shape as app/services/ai.py

`extract_acoustic_features()` is soft-fail: a missing/unreadable file, an
unsupported/corrupt audio format, a missing `ffmpeg` binary, a
silent/too-short recording, or any numpy/subprocess error returns None —
NEVER raises. Callers (app/routers/entries.py) must treat None as
"acoustic analysis unavailable" and continue with the transcript-only
rule/AI path unaffected — this feature must never be able to break entry
submission.

## What's computed and why

- **pause_ratio**: fraction of the recording's total duration that falls
  in silent/low-energy gaps between voiced segments, via frame-level RMS
  energy thresholded at `SILENCE_THRESHOLD_DB` below the recording's own
  peak frame energy (same idea as librosa.effects.split's top_db
  parameter, hand-rolled here). Proxy for speaking rate/fluency — long
  pauses can indicate breathlessness (needing to stop and catch a breath)
  or fatigue (slowed, effortful speech), per the task's own hypothesis.
  NOT the same as a rate-of-words measure (no ASR/forced-alignment here,
  only the on-device transcript, which carries no timing) — this is the
  closest signal-processing proxy available without one.
- **speaking_rate_segments_per_min**: count of distinct voiced segments
  per minute (from the same silence classification) — a coarse fluency
  proxy (fewer, longer segments = more continuous speech; many short
  segments = fragmented, effortful speech), not a true words-per-minute
  rate.
- **energy_rms_variance** / **energy_cv**: variance (and the
  scale-invariant coefficient of variation = std/mean) of frame-level RMS
  energy, computed over VOICED frames only (silence excluded — see the
  code comment where this is computed for why including silent frames
  would make this measure the trivial "speech is louder than pauses"
  fact instead of the intended "how flat is the energy WITHIN speech").
  CV is used for the derived flag rather than raw variance, since raw
  RMS is dependent on device mic gain/distance and not comparable
  device-to-device or patient-to-patient — CV is not.
- **pitch_mean_hz** / **pitch_variability_hz**: mean and standard
  deviation of the fundamental frequency (f0), estimated per-frame via
  time-domain autocorrelation (voiced frames only — frames classified
  silent by the energy threshold above are skipped, and a frame whose
  autocorrelation peak isn't strong/periodic enough is treated as
  unvoiced and skipped too). This is a simpler, less accurate method than
  a research-grade pitch tracker (e.g. librosa's pYIN, which this module
  originally used before the dependency pivot above) — autocorrelation
  pitch tracking is well-established and adequate for a single, fairly
  clean voice signal (which a phone-mic Voice Diary recording is), but
  can be less robust on noisy/multi-speaker/very-low-amplitude audio.
  Flagging this trade-off explicitly rather than presenting it as
  equivalent to a proper pitch tracker. Flat, narrow pitch variability is
  a classic "flat affect" / fatigue speech marker; too few voiced frames
  with a trustworthy pitch estimate is treated as "unavailable" (None)
  rather than forced to a number.

## Derived flag: possible_fatigue_or_breathlessness

`pause_ratio >= PAUSE_RATIO_HIGH_THRESHOLD AND energy_cv <=
ENERGY_CV_LOW_THRESHOLD` — long pauses paired with flat/quiet vocal
energy, per the task's own example hypothesis. **Every threshold below
is a Claude Code proposal, NOT clinically or empirically validated —
there is no labeled training data, no clinician sign-off, and no
comparison against a real patient population. Flagging clearly for
review, same as every other proposed threshold in app/services/rules.py.**
Deliberately conservative in how it's used downstream: this flag only
ever adds a small number of points to the rule engine's existing
Layer-B composite score (app/services/rules.py) — it can NEVER trigger a
hard Red flag on its own, exactly because it has no evidence base backing
it the way the doc-sourced red flags do.
"""

from __future__ import annotations

import logging
import shutil
import subprocess
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

logger = logging.getLogger(__name__)

# --- Proposed thresholds — NEEDS REVIEW, no clinician/training-data basis ---
# "Long pauses": typical conversational speech runs roughly 10-20% silence
# (breath groups, punctuation-equivalent pauses). Proposed as "notably
# higher than that" — arbitrary, not doc-sourced, not derived from any
# recorded patient sample.
PAUSE_RATIO_HIGH_THRESHOLD = 0.35
# "Low energy variance" expressed as coefficient of variation (std/mean),
# device-gain-invariant. Originally proposed at 0.15 as a pure guess;
# RAISED to 0.20 after this pass's own verification against a deliberately
# extreme synthetic "flat, quiet, long-paused" test recording (see
# context/decisions-log.md) — even that near-monotone sample only reached
# energy_cv≈0.16, computed over voiced frames only (frame-boundary
# attack/release transients at each phrase's onset/offset appear to set a
# practical floor on how low frame-level CV gets, at these frame/hop
# settings, even for genuinely flat-sounding audio). 0.20 is still an
# UNVALIDATED guess, now informed by one synthetic calibration point
# rather than pure intuition — not clinician/training-data-confirmed.
ENERGY_CV_LOW_THRESHOLD = 0.20
# A recording this short doesn't carry enough signal for any of the above
# to be meaningful — skip the derived flag (features are still returned).
MIN_DURATION_FOR_FLAG_SECONDS = 3.0
# Silence-classification sensitivity (dB below the recording's own peak
# frame energy) — same role as librosa.effects.split's top_db.
SILENCE_THRESHOLD_DB = 40

# Framing (samples, at the fixed decode rate below).
DECODE_SAMPLE_RATE = 16000
FRAME_LENGTH = 2048
HOP_LENGTH = 512

# Autocorrelation pitch search range (human voice fundamental frequency).
PITCH_FMIN_HZ = 65.0
PITCH_FMAX_HZ = 400.0
# How strong the autocorrelation peak must be, relative to zero-lag
# energy, to trust a frame as voiced/periodic rather than noise.
PITCH_PERIODICITY_MIN_RATIO = 0.35
MIN_VOICED_PITCH_FRAMES = 10


@dataclass
class AcousticFeatures:
    duration_sec: float
    pause_ratio: float
    num_pauses: int
    speaking_rate_segments_per_min: float
    energy_rms_mean: float
    energy_rms_variance: float
    energy_cv: float | None  # None if energy_rms_mean is ~0 (silent file)
    pitch_mean_hz: float | None  # None if too few voiced frames to trust
    pitch_variability_hz: float | None
    possible_fatigue_or_breathlessness: bool

    def to_dict(self) -> dict:
        return asdict(self)


def _decode_to_mono_pcm(file_path: str, tmp_wav_path: str) -> bool:
    """
    Shells out to system ffmpeg to decode ANY input format (m4a/aac/wav/
    mp3/ogg/webm — whatever the mobile recorder produced) to a mono,
    16kHz, 16-bit PCM WAV file. Returns False (never raises) if ffmpeg is
    missing or decoding fails for any reason.
    """
    if shutil.which("ffmpeg") is None:
        logger.warning("ffmpeg binary not found on PATH; acoustic analysis unavailable")
        return False
    try:
        result = subprocess.run(
            [
                "ffmpeg", "-v", "error", "-y",
                "-i", file_path,
                "-ac", "1",
                "-ar", str(DECODE_SAMPLE_RATE),
                "-f", "wav",
                tmp_wav_path,
            ],
            capture_output=True,
            timeout=30,
        )
        return result.returncode == 0 and Path(tmp_wav_path).stat().st_size > 44  # > WAV header alone
    except Exception:  # noqa: BLE001
        logger.warning("ffmpeg decode failed for %s", file_path, exc_info=True)
        return False


def _autocorr_pitch(frame, sr: int):  # noqa: ANN001 - numpy array, imported lazily
    """
    Time-domain autocorrelation pitch estimate for one frame. Returns a
    float Hz or None if the frame isn't periodic/voiced enough to trust.
    Deliberately simple — see module docstring's "pitch" section for the
    accuracy trade-off versus a research-grade tracker.
    """
    import numpy as np

    frame = frame - np.mean(frame)
    energy = float(np.dot(frame, frame))
    if energy <= 1e-9:
        return None

    corr = np.correlate(frame, frame, mode="full")
    corr = corr[len(corr) // 2:]

    min_lag = int(sr / PITCH_FMAX_HZ)
    max_lag = int(sr / PITCH_FMIN_HZ)
    if max_lag >= len(corr) or min_lag >= max_lag:
        return None

    segment = corr[min_lag:max_lag]
    if segment.size == 0:
        return None
    peak_offset = int(np.argmax(segment))
    peak_val = float(segment[peak_offset])
    if corr[0] <= 0 or peak_val <= PITCH_PERIODICITY_MIN_RATIO * corr[0]:
        return None  # not periodic enough to trust as voiced speech

    lag = min_lag + peak_offset
    if lag <= 0:
        return None
    return sr / lag


def extract_acoustic_features(file_path: str) -> AcousticFeatures | None:
    """
    Load an audio file and compute deterministic acoustic features.
    Soft-fail: returns None on any error (missing file, unreadable/corrupt
    audio, missing ffmpeg, too-short/silent recording) — never raises. See
    module docstring for the fallback contract every caller must honor.
    """
    try:
        # Imported lazily (function-local, not module-level) — a missing or
        # broken numpy install must not break importing this module at
        # all, since app/routers/entries.py imports it unconditionally at
        # app startup. A module-level `import numpy` would take down the
        # ENTIRE backend (including the already-verified transcript-only
        # path) if it failed to install — exactly the core-loop risk this
        # feature must not create. See context/decisions-log.md.
        import numpy as np
    except Exception:  # noqa: BLE001
        logger.warning("numpy not importable; acoustic analysis unavailable", exc_info=True)
        return None

    try:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_wav = str(Path(tmp_dir) / "decoded.wav")
            if not _decode_to_mono_pcm(file_path, tmp_wav):
                return None

            import wave

            with wave.open(tmp_wav, "rb") as wf:
                sr = wf.getframerate()
                n_frames = wf.getnframes()
                raw = wf.readframes(n_frames)
            samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0

        if samples.size == 0:
            logger.warning("Empty decoded audio buffer for acoustic analysis: %s", file_path)
            return None

        duration_sec = float(len(samples) / sr) if sr else 0.0
        if duration_sec <= 0:
            return None

        # --- Frame the signal (fixed length/hop) ----------------------
        n_frame_starts = max(0, 1 + (len(samples) - FRAME_LENGTH) // HOP_LENGTH)
        if n_frame_starts < 2:
            logger.info("Recording too short to frame for acoustic analysis: %s", file_path)
            return None
        frame_starts = np.arange(n_frame_starts) * HOP_LENGTH
        frames = np.stack([samples[s:s + FRAME_LENGTH] for s in frame_starts])

        rms = np.sqrt(np.mean(frames ** 2, axis=1))

        # --- Pause ratio / speaking-rate proxy via energy thresholding --
        peak_rms = float(np.max(rms)) if rms.size else 0.0
        threshold = peak_rms * (10 ** (-SILENCE_THRESHOLD_DB / 20)) if peak_rms > 0 else 0.0
        voiced_mask = rms > threshold
        voiced_frame_count = int(np.sum(voiced_mask))
        pause_ratio = max(0.0, min(1.0, 1.0 - (voiced_frame_count / len(rms))))

        # --- Energy/amplitude variance — VOICED frames only ---------------
        # Deliberately excludes silent/paused frames: including them would
        # mean a recording with MORE pauses mechanically gets a HIGHER
        # variance/CV (large swings between near-zero silent frames and
        # louder voiced frames), which is the opposite of what "flat vocal
        # energy" is meant to capture and would make the derived flag below
        # nearly impossible to trigger on a genuinely long-paused recording
        # (caught by testing against a real synthetic "exaggerated pauses"
        # sample during this feature's own verification — see
        # context/decisions-log.md). This measures variability WITHIN
        # speech, not the (trivial, always-true) fact that speech is louder
        # than silence.
        voiced_rms = rms[voiced_mask]
        if voiced_rms.size > 0:
            energy_mean = float(np.mean(voiced_rms))
            energy_variance = float(np.var(voiced_rms))
            energy_cv = (float(np.std(voiced_rms)) / energy_mean) if energy_mean > 1e-6 else None
        else:
            energy_mean = 0.0
            energy_variance = 0.0
            energy_cv = None

        # Count contiguous voiced runs (segments), same concept as
        # librosa.effects.split's interval count.
        num_segments = int(np.sum(np.diff(voiced_mask.astype(int)) == 1)) + (1 if voiced_mask[0] else 0)
        speaking_rate = (num_segments / duration_sec) * 60.0 if duration_sec else 0.0
        num_pauses = max(0, num_segments - 1)

        # --- Pitch variability (voiced frames only) ----------------------
        pitch_estimates = []
        for i in np.where(voiced_mask)[0]:
            f0 = _autocorr_pitch(frames[i], sr)
            if f0 is not None:
                pitch_estimates.append(f0)

        pitch_mean: float | None = None
        pitch_var: float | None = None
        if len(pitch_estimates) >= MIN_VOICED_PITCH_FRAMES:
            arr = np.array(pitch_estimates)
            pitch_mean = float(np.mean(arr))
            pitch_var = float(np.std(arr))

        flag = (
            duration_sec >= MIN_DURATION_FOR_FLAG_SECONDS
            and pause_ratio >= PAUSE_RATIO_HIGH_THRESHOLD
            and energy_cv is not None
            and energy_cv <= ENERGY_CV_LOW_THRESHOLD
        )

        return AcousticFeatures(
            duration_sec=round(duration_sec, 2),
            pause_ratio=round(pause_ratio, 3),
            num_pauses=num_pauses,
            speaking_rate_segments_per_min=round(speaking_rate, 1),
            energy_rms_mean=round(energy_mean, 5),
            energy_rms_variance=round(energy_variance, 6),
            energy_cv=round(energy_cv, 3) if energy_cv is not None else None,
            pitch_mean_hz=round(pitch_mean, 1) if pitch_mean is not None else None,
            pitch_variability_hz=round(pitch_var, 1) if pitch_var is not None else None,
            possible_fatigue_or_breathlessness=flag,
        )
    except Exception:  # noqa: BLE001 - any unexpected numeric/subprocess error
        logger.warning("Acoustic feature extraction failed for %s", file_path, exc_info=True)
        return None
