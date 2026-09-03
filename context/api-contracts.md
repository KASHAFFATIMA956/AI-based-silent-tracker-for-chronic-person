# API Contracts

Every endpoint the backend exposes: path, method, auth requirement, request/response
shape. Update this alongside `app/routers/` and `app/schemas/` as endpoints are added —
don't let this drift from the code.

---

## Auth

### `POST /auth/login`
**Auth**: none (this is how you get a token).

Request body (`LoginRequest`):
```json
{ "phone_or_email": "zubaida.b@roznoor.care", "password": "RozNoor@123" }
```

Response `200` (`TokenResponse`):
```json
{
  "access_token": "<jwt>",
  "token_type": "bearer",
  "expires_in": 86400,
  "user_id": 6,
  "role": "patient",
  "name": "Zubaida Bibi"
}
```

Response `401` — wrong `phone_or_email` or `password` (same message for both, to avoid
leaking which one was wrong):
```json
{ "detail": "Incorrect phone/email or password" }
```

### `GET /auth/me`
**Auth**: required (any role). Returns the caller's own identity — also a convenient
way to check whether a token is still valid.

Response `200` (`CurrentUserResponse`):
```json
{
  "id": 6,
  "name": "Zubaida Bibi",
  "role": "patient",
  "phone_or_email": "zubaida.b@roznoor.care",
  "language_preference": "roman_urdu",
  "patient_id": 2
}
```
`patient_id` added 2026-08-25 (Flutter patient-app pass) — the caller's own
`patients.id` when role is `patient` (`patients.user_id` match) or `attendant`
(`patients.attendant_user_id` match), else `null`. Added because there was
otherwise no way for a freshly logged-in patient/attendant client to discover
which `patient_id` to call every other patient-scoped route with —
`POST /auth/login` only returns `user_id`. See [[decisions-log]].

Response `401` — missing/invalid/expired token: `{"detail": "Not authenticated"}` /
`{"detail": "Token expired"}`.

---

## Patients

### `GET /patients/{patient_id}`
**Auth**: required. RBAC via `get_authorized_patient`:
- `admin` — always allowed.
- `doctor` — allowed only if `patients.assigned_doctor_id == current_user.id`.
- `patient` — allowed only if `patients.user_id == current_user.id`.
- `attendant` — allowed only if `patients.attendant_user_id == current_user.id`
  (not in the original spec, added for schema consistency — see
  [[decisions-log]]).

This endpoint exists to prove the RBAC dependency end-to-end; it is intentionally
minimal. Full patient CRUD/list endpoints (create, update, doctor's roster list,
search/filter) are a separate future task.

Response `200` (`PatientOut`):
```json
{
  "id": 2,
  "mr_number": "MR 40-2291",
  "diagnosis": "Heart failure, post-discharge",
  "age": 68,
  "baseline_stage": "personalized",
  "day_count": 19,
  "assigned_doctor_id": 1,
  "user_id": 6,
  "attendant_user_id": 4,
  "emergency_contact_name": "Rescue 1122",
  "emergency_contact_phone": "1122",
  "medication_info": "Furosemide 40mg - morning; Bisoprolol 2.5mg - morning; Ramipril 5mg - night",
  "attendant_name": "Imran Zubair",
  "assigned_doctor_name": "Dr. Ayesha Farooq"
}
```
`emergency_contact_name`/`emergency_contact_phone`/`medication_info` (already-
existing `patients` columns) and computed `attendant_name`/
`assigned_doctor_name` added 2026-08-25 (Flutter patient-app pass) — needed
for the Profile screen. See [[decisions-log]]. Still no `PATCH
/patients/{id}` — this endpoint is read-only.

Response `403` — authenticated but not authorized for this patient:
```json
{ "detail": "Not authorized to access this patient" }
```

Response `404` — no such patient: `{"detail": "Patient not found"}`.

### `GET /patients/{patient_id}/symptom-checklist`
**Auth**: required. Same RBAC as `GET /patients/{patient_id}`
(`get_authorized_patient`). Added 2026-08-25 (Flutter patient-app pass) so a
client can render the diagnosis-specific symptom checklist (Quick Check-in,
Voice Diary) without hardcoding one — reuses the exact same
`diagnosis_key`/`CHECKLIST_DIAGNOSIS_SEARCH_TERMS` lookup `POST /entries`
already uses internally, so the checklist shown always matches what
`symptom_ids` values `POST /entries` will actually accept. See
[[decisions-log]].

Response `200` (`list[SymptomChecklistItem]`) — empty list for a diagnosis
with no defined checklist (the generic ruleset), not an error:
```json
[
  { "id": 1, "symptom_name": "Breathlessness" },
  { "id": 2, "symptom_name": "Ankle swelling" },
  { "id": 3, "symptom_name": "Chest pain" }
]
```

Response `403`/`404` — same as `GET /patients/{patient_id}`.

### `POST /patients/{patient_id}/ai-summary`
**Auth**: required. Same RBAC as `GET /patients/{patient_id}` above. The "Generate AI
Summary" doctor-facing button from the project doc/UI prototype — also usable for the
patient's own Result-screen-style summary.

No request body. Reads the patient's last 10 entries + all `baseline_history` rows
(+ as of 2026-08-25, any `ai_results.acoustic_features` for those entries — purely
additive prompt context, see `context/decisions-log.md`; the system prompt explicitly
instructs Claude to describe it only as a signal-processing estimate, never as an AI
judgment or diagnosis), calls Claude for a plain-language paragraph. **Never returns a
500 for an AI failure** — soft-fails to `available: false`.

Response `200` (`AiSummaryOut`), success:
```json
{
  "available": true,
  "summary_text": "Over the past week Zubaida Bibi's tracked scores have stayed inside her learned bands... Medication was logged as taken at every entry except 18 Aug (missed)... The risk escalation attached to this record was generated by the rule and baseline layers... this summary only condenses those already-computed findings for your review and does not itself assign risk.",
  "fallback_message": null
}
```

Response `200` (`AiSummaryOut`), Claude API unavailable/unconfigured/errored:
```json
{
  "available": false,
  "summary_text": null,
  "fallback_message": "AI summary is unavailable right now (Claude API unreachable or not configured). Rule-based risk data for this patient is unaffected and still up to date."
}
```

Response `403`/`404` — same as `GET /patients/{patient_id}`.

---

## Entries (rule-based safety engine)

### `POST /entries`
**Auth**: required, role-gated to `patient` and `attendant` only (`require_roles`).
`patient_id` is in the request body (not the URL), so authorization is enforced via
`is_authorized_for_patient` (same rule as `get_authorized_patient`, factored out — see
[[decisions-log]]): a patient may only submit for their own `patient_id`; an attendant
only for a patient where `attendant_user_id` matches them.

Runs the full rule-based safety pipeline synchronously, plus an AI-interpretation
step for **voice** entries (added 2026-08-25): red-flag rules -> baseline
deviation/streak/adherence scoring -> risk_results -> alerts if non-Green -> folds the
entry into baseline_history/day_count/baseline_stage for next time. For a voice entry,
Claude first extracts which of the diagnosis's checklist symptoms the transcript
describes; those matches are folded into the SAME symptom set the rule engine scores
(including hard red-flags — a transcript mentioning chest pain triggers the Red flag
even with no manual checklist tick) and an `ai_results` row is written.
`risk_results.source` is `'merged'` when that AI step actually ran this call, else
`'rule'` (missing/invalid API key, any API error/timeout, a quick entry, or no
checklist defined for the diagnosis — all soft-fail to rule-only, never a 500). See
`app/services/rules.py`, `app/services/baseline.py`, and `app/services/ai.py`.

Request body (`EntryCreate`):
```json
{
  "patient_id": 2,
  "entry_type": "quick",
  "timestamp": "2026-08-24T18:00:00Z",
  "sleep_value": 7.0,
  "energy_value": 4,
  "mood_value": 4,
  "appetite_value": 4,
  "mobility_value": 4,
  "weight_value": 64.4,
  "medicine_status": "taken",
  "symptom_ids": []
}
```
- `timestamp` optional — defaults to submission time; explicit values allowed for
  demo/backdating.
- `entry_type: "voice"` requires non-empty `raw_transcript`; `entry_type: "quick"`
  requires at least one of sleep/energy/mood/appetite/mobility/**weight** (any one —
  a weight-only morning weigh-in with no sliders is a valid quick entry on its own).
- Slider values are bounds-checked: `sleep_value` 0-24 (hours), energy/mood/appetite/
  mobility 1-5 (confirmed scale — see [[decisions-log]]), `weight_value` 0-300 (kg, a
  sanity check not a clinical range). `weight_value` added 2026-08-24 — not gated to
  `entry_type` the way the sliders are.
- `symptom_ids` reference `symptom_checklist_options.id`; accepted on any
  `entry_type` (see [[decisions-log]] for why voice entries can carry them too, in
  the absence of AI extraction).

Response `201` (`EntryOut`) — the created entry plus its computed risk result:
```json
{
  "id": 21,
  "patient_id": 2,
  "entry_type": "voice",
  "timestamp": "2026-08-24T16:34:18.343810",
  "raw_transcript": "Seene mein bohot dard hai",
  "transcript_translation": "There is a lot of chest pain",
  "sleep_value": null, "energy_value": null, "mood_value": null,
  "appetite_value": null, "mobility_value": null, "weight_value": null,
  "medicine_status": "taken",
  "symptom_names": ["Chest pain"],
  "risk_result": {
    "risk_level": "Red",
    "risk_title": "Please seek care now",
    "risk_message": "A critical concern was detected. Contact emergency services or your medical provider immediately.",
    "reasoning": "Chest pain is a clinician-set red flag for this diagnosis. This does not wait for a baseline comparison.",
    "source": "rule"
  },
  "has_audio": false,
  "acoustic_features": null
}
```
`has_audio`/`acoustic_features` added 2026-08-25 (acoustic-analysis pass) — always
`false`/`null` on the direct `POST /entries` response, since audio is attached by a
SEPARATE call afterward (see `POST /entries/{entry_id}/audio` below); never `true` on
this endpoint's own response.

Weight red-flag example — same shape, triggered by `weight_value` alone (a rise of
>=2.0kg within a trailing 3-day window, compared against the lowest reading in that
window):
```json
{
  "weight_value": 67.0,
  "risk_result": {
    "risk_level": "Red",
    "risk_title": "Please seek care now",
    "reasoning": "Weight +3.2kg within 3 days (63.8kg -> 67.0kg). This does not wait for a baseline comparison.",
    "source": "rule"
  }
}
```

AI-merged example — a voice entry with NO `symptom_ids` ticked, where Claude detected
the symptoms from the transcript itself (`source: "merged"`, and note `symptom_names`
is populated even though the request sent none):
```json
{
  "raw_transcript": "Aaj subah se sans lene mein bohot takleef ho rahi hai aur mere pair bhi sujay huay hain, thakan bhi zyada hai.",
  "symptom_ids": [],
  "symptom_names": ["Ankle swelling", "Breathlessness"],
  "risk_result": {
    "risk_level": "Yellow",
    "reasoning": "Ankle swelling; breathlessness.",
    "source": "merged"
  }
}
```

Response `422` — Pydantic validation failure (missing transcript on a voice entry, no
slider/weight values on a quick entry, a value outside its bounds).

Response `403` — role isn't patient/attendant, or is but not authorized for this
`patient_id`: `{"detail": "Not authorized for this action"}` /
`{"detail": "Not authorized to submit entries for this patient"}`.

Response `404` — no such patient: `{"detail": "Patient not found"}`.

### `GET /entries/{patient_id}/timeline`
**Auth**: required. Same RBAC as `GET /patients/{patient_id}` (`get_authorized_patient`
— admin/assigned-doctor/self-patient/linked-attendant).

Returns every entry for the patient, newest first, each with its symptom names and
risk result (same `EntryOut` shape as the `POST /entries` response, as a list).

Response `200`:
```json
[
  { "id": 24, "entry_type": "quick", "timestamp": "...", "...": "...", "risk_result": { "risk_level": "Green", "...": "..." } },
  { "id": 23, "entry_type": "voice", "timestamp": "...", "...": "...", "risk_result": { "risk_level": "Red", "...": "..." } }
]
```

Response `403`/`404` — same as `GET /patients/{patient_id}`.

### `POST /entries/{entry_id}/audio`
**Auth**: required, role-gated to `patient`/`attendant` (`require_roles`), ownership
enforced via `is_authorized_for_patient` against the entry's own patient (same policy
as `POST /entries`, resolved from the entry rather than a body field). Added
2026-08-25 (acoustic-analysis pass) — see `context/decisions-log.md` for why this is a
SEPARATE call rather than merged into `POST /entries`.

Attaches a raw audio recording to an already-created **voice** entry (400 if called on
a quick entry) and runs deterministic signal-processing feature extraction
(`app/services/audio_analysis.py` — numpy + a system `ffmpeg` subprocess for decoding,
NOT librosa, NOT a machine-learning model — see `context/decisions-log.md` for the
mid-build pivot away from librosa). Re-runs the rule engine with the extracted
acoustic signal folded in as an additional (Layer-B only, never hard-flag) score
contributor, and updates the entry's existing `risk_result`/`alert` in place — does
not create a second risk_result row. **Soft-fail by design**: if the file can't be
saved (500) that's the only hard failure; if acoustic extraction itself fails
(corrupt/unreadable audio, `ffmpeg` missing, etc.) the file is still saved
(`has_audio` becomes `true`) but `risk_result` and `acoustic_features` are left
exactly as `POST /entries` computed them — this endpoint can only ever ADD signal,
never remove or invalidate what already exists. Verified for real, including this
exact soft-fail path with a genuinely corrupt upload — see `context/decisions-log.md`.

Request: `multipart/form-data`, one field `audio_file` (the recording — m4a/aac/wav/
mp3/ogg/webm all accepted; decoded via `ffmpeg`, which must be on PATH wherever this
backend runs).

Response `200` (`EntryOut`) — the full updated entry, same shape as `POST /entries`,
now with `has_audio: true` and populated `acoustic_features` (if extraction
succeeded):
```json
{
  "id": 21,
  "entry_type": "voice",
  "has_audio": true,
  "acoustic_features": {
    "duration_sec": 9.4,
    "pause_ratio": 0.52,
    "num_pauses": 5,
    "speaking_rate_segments_per_min": 25.5,
    "energy_rms_mean": 0.021,
    "energy_rms_variance": 0.00004,
    "energy_cv": 0.09,
    "pitch_mean_hz": 162.3,
    "pitch_variability_hz": 6.1,
    "possible_fatigue_or_breathlessness": true
  },
  "risk_result": {
    "risk_level": "Yellow",
    "reasoning": "Voice recording pause ratio 52% with flat vocal energy (cv=0.09) — possible fatigue/breathlessness pattern, signal-processing estimate, not clinically validated.",
    "source": "merged"
  }
}
```
`acoustic_features` keys are documented in full on `AiResult.acoustic_features`'s model
docstring (`app/models/ai_result.py`) — every threshold behind
`possible_fatigue_or_breathlessness` is a Claude Code proposal needing review, see
`context/decisions-log.md`. `source` becomes `"merged"` whenever the acoustic flag
fires (or was already `"merged"` from the AI transcript-extraction step) — this
endpoint never introduces a third `source` value.

Response `400` — entry exists but isn't a voice entry, or the uploaded file is empty:
`{"detail": "Audio can only be attached to a voice entry"}` /
`{"detail": "Uploaded audio file is empty"}`.
Response `403` — not authorized for this entry's patient:
`{"detail": "Not authorized to attach audio to this entry"}`.
Response `404` — no such entry: `{"detail": "Entry not found"}`.
Response `500` — the file could not be saved to disk (hackathon-scope local-disk
storage — see `context/decisions-log.md`): `{"detail": "Failed to save audio file"}`.

### `POST /patients/{patient_id}/notes`
**Auth**: required, doctor/admin ONLY (`get_clinician_patient`) — narrower than
every other patient-scoped route above: a doctor must be this patient's
`assigned_doctor_id`; admin always allowed; **patient/attendant get 403 even for
their own record** (this is a clinician-write action, not a read).

Request body (`DoctorNoteCreate`):
```json
{ "note_text": "Discussed weight trend, advised daily weigh-ins." }
```

Response `201` (`DoctorNoteOut`):
```json
{
  "id": 4,
  "patient_id": 2,
  "doctor_id": 1,
  "doctor_name": "Dr. Ayesha Farooq",
  "note_text": "Discussed weight trend, advised daily weigh-ins.",
  "created_at": "2026-08-25T10:00:00Z"
}
```

Response `403` — role isn't doctor/admin, or is a doctor but not this patient's
assigned doctor: `{"detail": "Not authorized to manage this patient's clinical notes"}`.
Response `404` — no such patient.

### `GET /patients/{patient_id}/notes`
**Auth**: same as `POST` above (doctor/admin only, no patient/attendant access).
Returns every note for the patient, newest first.

Response `200`: `list[DoctorNoteOut]` (same shape as the `POST` response).

---

## Doctors

### `GET /doctors/{doctor_id}/patients`
**Auth**: required. RBAC via `get_authorized_doctor`: admin always; doctor only
for their own `doctor_id`; patient/attendant always 403 (not a narrowed
version of patient access — these roles have no reason to call this at all).

Doctor's roster — every patient with `assigned_doctor_id == doctor_id`, each
with their latest entry's risk level/reasoning, sorted most-recently-active
first (patients with no entries yet sort last).

Response `200` (`list[DoctorPatientRosterItem]`):
```json
[
  {
    "patient_id": 2,
    "name": "Zubaida Bibi",
    "mr_number": "MR 40-2291",
    "age": 68,
    "diagnosis": "Heart failure, post-discharge",
    "day_count": 19,
    "baseline_stage": "personalized",
    "latest_risk_level": "Orange",
    "latest_reasoning": "Weight +2.4kg within 5 days...",
    "last_entry_timestamp": "2026-08-24T09:14:00Z"
  }
]
```

Response `403` — not this doctor and not admin, or role is patient/attendant:
`{"detail": "Not authorized to access this doctor's data"}`.
Response `404` — no such doctor (or the user id given isn't a doctor at all):
`{"detail": "Doctor not found"}`.

### `GET /doctors/{doctor_id}/alerts`
**Auth**: same as above (`get_authorized_doctor`). Alerts across the doctor's
own patients only. Optional query param `?reviewed=true` / `?reviewed=false` to
filter; omit for all. Newest first.

Response `200` (`list[AlertOut]`):
```json
[
  {
    "id": 5,
    "patient_id": 2,
    "patient_name": "Zubaida Bibi",
    "entry_id": 18,
    "risk_level": "Orange",
    "alert_text": "Weight +2.4 kg in 5 days with falling sleep and sustained low energy.",
    "source_rule": "Baseline layer + weight red-flag rule",
    "reviewed": false,
    "created_at": "2026-08-24T09:14:00Z"
  }
]
```

Response `403`/`404` — same as `GET /doctors/{doctor_id}/patients`.

---

## Alerts

### `POST /alerts/{alert_id}/review`
**Auth**: required, `require_roles(doctor, admin)` + `is_authorized_clinician_for_patient`
(doctor must be the alert's patient's assigned doctor; admin always). Patient/
attendant always 403, even for their own alert.

No request body. Sets `alerts.reviewed = true`.

Response `200` (`AlertOut`) — the updated alert (same shape as above, `reviewed: true`).
Response `403` — wrong role, or a doctor who isn't this alert's patient's doctor:
`{"detail": "Not authorized to review this alert"}`.
Response `404` — no such alert: `{"detail": "Alert not found"}`.

---

## Admin

All three routes below: `require_roles(UserRole.admin)` — admin only, no exceptions.

### `GET /admin/users`
Every user, for the "People & roles" management screen. `linked_summary` is
computed per row (a doctor's assigned-patient count, a patient's assigned
doctor's name, an attendant's linked patient's name, or `"System"` for admin —
`null` if not yet linked to anything). `diagnosis` is only populated for
patient rows.

Response `200` (`list[AdminUserOut]`):
```json
[
  {
    "id": 6,
    "name": "Zubaida Bibi",
    "role": "patient",
    "phone_or_email": "zubaida.b@roznoor.care",
    "language_preference": "roman_urdu",
    "created_at": "2026-08-24T08:00:00Z",
    "linked_summary": "Dr. Ayesha Farooq",
    "diagnosis": "Heart failure, post-discharge"
  }
]
```

Response `403` — non-admin.

### `POST /admin/users`
Create a new user of any role. Reuses `app.core.security.hash_password` — no
separate hashing logic.

Request body (`AdminUserCreate`):
```json
{
  "name": "Dr. Test Newperson",
  "role": "doctor",
  "phone_or_email": "test.newdoctor@civilhosp.pk",
  "password": "RozNoor@123",
  "language_preference": "english"
}
```

Response `201` (`AdminUserOut`) — same shape as `GET /admin/users` rows (a
freshly created doctor shows `linked_summary: "0 patients"`).
Response `409` — `phone_or_email` already taken:
`{"detail": "A user with this phone/email already exists"}`.
Response `403` — non-admin. Response `422` — Pydantic validation failure.

### `PATCH /admin/users/{user_id}`
Partial edit. Fields: `name`, `role`, `phone_or_email`, `language_preference` —
**no `status` field** (`users` has no such column; not added — see
[[decisions-log]]). At least one field required.

Request body (`AdminUserUpdate`), any subset:
```json
{ "name": "Dr. Test Renamed" }
```

Response `200` (`AdminUserOut`) — the updated user.
Response `409` — the new `phone_or_email` collides with a different user.
Response `404` — no such user. Response `403` — non-admin.
Response `422` — an empty body (the "at least one field" validator).

---

## Auth header convention
All protected routes read `Authorization: Bearer <access_token>`. There is no cookie
auth, no API key, no OAuth2 form login (`/auth/login` takes a JSON body, not
`application/x-www-form-urlencoded`).

## Verified (2026-08-24, auth pass)
Manually exercised against a throwaway local Postgres + running FastAPI instance: login
success/failure, `/auth/me` with/without a token, and the full RBAC matrix on
`/patients/{id}` — patient self-access (200), patient cross-access (403), doctor
own-patient (200), doctor other-doctor's-patient (403), admin any-patient (200),
nonexistent patient (404), garbage token (401). All matched expected behavior.

## Verified (2026-08-24, rules-engine pass)
Manually exercised `POST /entries` and `GET /entries/{patient_id}/timeline` against a
fresh throwaway Postgres + running FastAPI instance (no schema changes needed — every
column this pass touches already existed): chest-pain hard-flag -> Red; plain quick
entry -> Green; combined baseline-deviation + below-band streak + missed-dose streak ->
Yellow with correct multi-part reasoning; RBAC across patient-self (201), attendant of
record (201), doctor (403, role-gated out entirely), unrelated patient (403); Pydantic
422s for a transcript-less voice entry, a value-less quick entry, and an out-of-range
slider value; timeline returns newest-first with correct nested risk_result; alerts
rows created only for non-Green outcomes; unauthenticated request -> 401.

## Verified (2026-08-24, weight-tracking pass)
Manually exercised the weight red-flag via real `POST /entries` calls against a fresh
throwaway Postgres (migration applied on top of the prior schema, not a from-scratch
DB): a clear +3.2kg jump -> Red with correct reasoning; the exact 2.0kg/3-day boundary
-> Red, 1.9kg -> not Red (confirms `>=`, no off-by-one); a large gain spread over 10+
days (outside the 3-day window) -> correctly NOT flagged; a stable patient's normal
small weight change -> Green (no false positive); `baseline_history`'s `weight` row
updates correctly; timeline returns `weight_value` on every entry; a weight-only quick
entry (no sliders) is accepted as valid.

## Verified (2026-08-25, AI layer pass)
Fallback path (no API key, then a deliberately invalid one causing a real 401 from
Anthropic): both correctly fell back to `source: "rule"`, no `ai_results` row, no
crash, request completed in ~0.6s (no hang), failure logged server-side; `ai-summary`
returned `available: false` with a 200, not a 500. Success path (real Anthropic API
key, provided by the user for this test and removed again afterward — never logged or
committed): a Roman Urdu transcript describing breathlessness/swelling/fatigue with NO
manual `symptom_ids` correctly produced matched checklist symptoms + free-text tags,
`source: "merged"`, Yellow; a Roman Urdu chest-pain transcript with NO manual tick
correctly triggered the hard Red flag via AI-detected symptoms alone (the key safety
scenario — AI evidence feeding the same rule engine, never bypassing it); a benign
"I'm fine" transcript correctly produced zero symptom matches (no false positive);
`POST /patients/{id}/ai-summary` produced a real, accurately-grounded paragraph
(correct weight numbers/band, correctly attributed the risk escalation to the rule/
baseline layers rather than itself). Quick entries never invoke AI at all (verified
implicitly throughout — every quick entry in every pass stayed `source: "rule"`). The
"no checklist defined for this diagnosis" skip path (generic-ruleset patients) was
**not** separately exercised this pass — it's a simple `if checklist_options:` guard,
low-risk, but flagging that it wasn't hit by a real request.
**Closed out 2026-08-25** — see the next section below.

## Verified (2026-08-25, doctor & admin routers pass)
Manually exercised every endpoint added this pass against a fresh throwaway Postgres +
running FastAPI instance, real HTTP requests, 48 checks total, **all passed on the
first run**:
- `GET /doctors/{id}/patients`: doctor sees exactly their own roster (right patient
  set, latest risk level/reasoning populated); another doctor -> 403; admin -> 200 for
  any doctor; a patient-role token -> 403 (blocked entirely, not narrowed); nonexistent
  doctor -> 404; unauthenticated -> 401.
- `GET /doctors/{id}/alerts` (+ `?reviewed=false` filter): doctor sees only their own
  patients' alerts, filter returns only matching rows; another doctor -> 403.
- `POST /alerts/{id}/review`: the assigned doctor -> 200 + `reviewed:true`; a different
  doctor on the same alert -> 403; a patient token -> 403; admin -> 200 on any alert;
  nonexistent alert -> 404.
- `POST`/`GET /patients/{id}/notes`: the patient's assigned doctor -> 201/200 (with
  correct `doctor_name`); a different doctor -> 403; **the patient herself -> 403**;
  **her linked attendant -> 403** (both correctly blocked from a clinician-only route
  despite having read access to her record elsewhere); admin -> 201 for any patient.
- `GET /admin/users`: returns all 10 seeded users; patient row's `linked_summary`
  correctly shows her assigned doctor's name + her `diagnosis`; doctor row shows
  `"4 patients"`; attendant row shows her linked patient's name; admin row shows
  `"System"`; a doctor or patient token -> 403; unauthenticated -> 401.
- `POST /admin/users`: creates a real user (`linked_summary: "0 patients"` for a fresh
  doctor); **the created password is a real usable bcrypt hash** — logged in with it
  immediately after creation; duplicate `phone_or_email` -> 409; non-admin -> 403.
- `PATCH /admin/users/{id}`: edits `name` -> 200 with the change reflected; colliding
  `phone_or_email` -> 409; nonexistent user -> 404; non-admin -> 403; empty body -> 422.
- **Closed out the AI-layer pass's flagged gap**: a voice entry submitted for a
  COPD-diagnosis patient (maps to the generic ruleset, no
  `CHECKLIST_DIAGNOSIS_SEARCH_TERMS` entry) correctly never called
  `ai_service.extract_symptoms()` — `risk_result.source` stayed `"rule"`, no
  `ai_results` row was written. No API key needed for this check since the guard
  skips before any Claude call would happen.

## Verified (2026-08-25, Flutter patient-app pass)
Backend additions (`patient_id` on `GET /auth/me`, extended `PatientOut`, new
`GET /patients/{id}/symptom-checklist`) verified via curl against a fresh
throwaway Postgres + running FastAPI instance, then again through the real
Flutter app end-to-end (see [[decisions-log]] for the full narrative): login
as a real patient account; `GET /auth/me` returning the correct `patient_id`;
the symptom checklist endpoint returning the real heart-failure checklist for
Zubaida Bibi; a quick check-in with "Chest pain" ticked producing a real
hard-Red-flag `POST /entries` result, correctly rendered on the Result
screen; a typed-fallback voice entry (`entry_type: "voice"`) producing a real
Green result with no false positive; the timeline endpoint reflecting every
entry submitted during the session, newest-first; a real doctor account
routed to the placeholder screen purely by JWT role via the clinician login
link, not by which form was used. No `ANTHROPIC_API_KEY` was configured this
session, so `source: "merged"` was not re-exercised (already verified with a
real key in the AI-layer pass above) — every entry submitted this pass
correctly stayed `source: "rule"`.

## Verified (2026-08-29, Flutter doctor-role pass)
No endpoints changed this pass (Flutter-only, per task scope) — the doctor
router/alerts/notes endpoints documented above were re-exercised with real
curl calls against a fresh throwaway Postgres + running FastAPI instance
before any Flutter code was written against them, then again through the
real Flutter app end-to-end (see `context/decisions-log.md` for the full
narrative): both seeded doctors' `GET /doctors/{id}/patients` /
`GET /doctors/{id}/alerts` returned only their own patients/alerts;
`POST /alerts/{id}/review` flipped `reviewed` for real (confirmed via a
direct Postgres `SELECT`, not just the response body); `POST`/`GET
/patients/{id}/notes` round-tripped a real note added through the mobile
UI. All response shapes matched this file's documented shapes exactly —
no drift found.

## Verified (2026-08-29, React web app pass)
No endpoints changed this pass (web-frontend-only, patient/attendant role,
no backend changes at all). Every endpoint the web patient screens call —
`POST /auth/login`, `GET /auth/me`, `GET /patients/{id}`,
`GET /patients/{id}/symptom-checklist`, `POST /entries`,
`POST /entries/{id}/audio`, `GET /entries/{patient_id}/timeline` — was
exercised for real through the actual browser UI (Chrome, via the
`claude-in-chrome` automation) against a fresh throwaway Postgres +
running FastAPI instance, driven through the Vite dev-server proxy (see
`context/decisions-log.md`, "web app CORS/proxy decision" — no CORS
middleware was added to the backend): real patient login (`zubaida.b@roznoor.care`)
and a deliberately wrong password (`401`, correct `"Incorrect phone/email
or password"` message rendered); a real doctor login
(`a.farooq@civilhosp.pk`) correctly routed to the placeholder screen purely
by JWT role, not by which login form was used; a Quick Check-in with
"Chest pain" ticked producing a real hard-Red-flag `POST /entries` result
end-to-end (`risk_level: "Red"`, correct reasoning text), rendered on the
Result screen; a typed-fallback Voice Diary entry (`entry_type: "voice"`,
no `ANTHROPIC_API_KEY` configured, so `source` stayed `"rule"`) producing a
correct Green result with no false positive; the timeline endpoint
reflecting every entry submitted during the session, newest-first,
including entries seeded by prior Flutter-app real-device passes (shared
backend/DB); the Profile screen's real `PatientOut` fields (medicines,
baseline status, day_count/baseline_stage advancing after a submission);
logout correctly clearing the session and redirecting to `/login`. No
console errors at any point (checked via `read_console_messages`, not just
visual inspection). **Not verified this pass**: `POST /entries/{id}/audio`
via a REAL browser microphone recording — no audio input hardware
available in the sandboxed browser environment used for this
verification, same category of gap as every mobile-app pass that lacked
mic hardware; the code path (Web Speech API → MediaRecorder → `FormData`
upload) was written and reviewed but not exercised with real audio this
session — see `context/decisions-log.md` ("Web voice capture") and
`context/pending-device-tests.md` for the follow-up item this adds.

## Verified (2026-08-29, React web app doctor-role pass)
No endpoints changed this pass (web-frontend-only, doctor role, no backend
changes). Every doctor endpoint — `GET /doctors/{id}/patients`,
`GET /doctors/{id}/alerts`, `POST /alerts/{id}/review`,
`POST`/`GET /patients/{id}/notes` — re-exercised with real curl calls
against the already-running backend before any React code was written
against them (all response shapes matched this file exactly), then again
through the real browser UI (Chrome, via `claude-in-chrome`): real doctor
login as Dr. Ayesha Farooq (clinician sign-in link) routed to the roster
purely by JWT role; roster showing her real 4 patients with correct
counts; patient detail for Zubaida Bibi showing real timeline/weight-sleep
trends/alert history/notes; **adding a note through the UI persisted for
real** — confirmed via a direct Postgres `SELECT` against `doctor_notes`,
not just the UI; **marking an alert reviewed persisted for real** —
confirmed via a direct Postgres `SELECT` against `alerts` (`reviewed`
flipped `true`), with the sidebar's live unread-count badge updating
immediately (5→4); the Unread/All alerts filter and the roster search
filter both worked correctly. **Account-switch scenario specifically
re-checked**: logged out, logged in as Dr. Hamza Iqbal — roster/alerts
correctly showed only his own 2 patients/2 alerts, zero stale trace of Dr.
Ayesha's data (this exact bug class was found and fixed in
`mobile_app/lib/screens/root_router.dart` — see `context/decisions-log.md`
for both the Flutter fix and this session's confirmation it doesn't
recur here). Also confirmed backend RBAC holds end-to-end from the
frontend: Dr. Hamza hitting a `GET /patients/2` (Dr. Ayesha's patient) via
direct URL got a real `403`, rendered gracefully, not someone else's
data. Zero console errors throughout. Full narrative, including two real
bugs found and fixed (a routing/dev-proxy path collision, and a missing
patient-name field worked around), in `context/decisions-log.md`.

## Verified (2026-08-29, React web app admin-role pass — final session)
No endpoints changed this pass (web-frontend-only, admin role, no backend
changes) — `GET/POST /admin/users` and `PATCH /admin/users/{id}` were
already complete and verified in the 2026-08-25 doctor & admin routers
pass and the 2026-08-29 Flutter admin-role pass; re-exercised with real
curl calls against the already-running backend before any React code was
written against them (all response shapes matched this file exactly),
then again through the real browser UI (Chrome, via `claude-in-chrome`):
real admin login (Sadia Kamran, clinician sign-in link) routed to
`/people` purely by JWT role; the list rendered all real users (seeded +
prior-session test rows) with correct computed `linked_summary`/
`diagnosis`; the search filter narrowed correctly; a full-page reload at
`/people` and a direct-URL load of `/people/new` both rendered the SPA
correctly (no dev-proxy collision — `/people` was checked against
`vite.config.js`'s proxy list before being picked, avoiding a repeat of
the doctor-role pass's routing bug); **a user of all four roles (patient/
doctor/attendant/admin) was created through the real "Invite a person"
form, and each one's password was independently confirmed to actually
work by logging in as that new user afterward** via curl (same pattern
every prior admin-role verification, backend and Flutter, has used) —
all four also confirmed present via a direct Postgres `SELECT`; **an
existing user was renamed and had its language preference changed
through the real "Edit person" form, confirmed persisted via a direct
Postgres `SELECT`**, not just the UI's own return-to-list; a freshly-
created test patient login correctly showed the existing "account isn't
linked to a patient record yet" fallback (expected — `POST /admin/users`
creates no `patients` row); a real seeded patient (Zubaida Bibi) login
immediately afterward correctly routed to the ordinary patient shell, and
a direct-URL navigation to `/people` while signed in as her fell through
to `/home`; **as defense-in-depth, a freshly-created non-admin (doctor and
patient) JWT was independently confirmed via curl to get a real `403`
from `GET`/`POST /admin/users`** (`{"detail":"Not authorized for this
action"}`); the account-switch scenario (patient → admin) reloaded a
fresh, correctly-populated list, not stale state; a doctor login
immediately after was unaffected by this session's `App.jsx` changes, and
a direct-URL navigation to `/people` while signed in as a doctor correctly
redirected to `/roster`. Zero console errors throughout. Full narrative,
including the one browser-automation timing quirk hit during verification
(not an app bug), in `context/decisions-log.md`.

**This completes all three roles (patient/doctor/admin) on BOTH platforms
— the entire frontend scope for this hackathon MVP is now built and
verified.**

## Verified (2026-08-29, Flutter admin-role pass)
No endpoints changed this pass (Flutter-only, admin role, no backend
changes) — `GET/POST /admin/users` and `PATCH /admin/users/{id}` were
already complete and verified in the 2026-08-25 doctor & admin routers
pass; re-exercised with real curl calls (login as the seeded admin,
list all 10 users, create one user of each of the four roles, PATCH a
rename, confirm via a direct Postgres `SELECT`) before any Flutter code
was written against them, then again through the real Flutter app
end-to-end: real admin login (Sadia Kamran, via the clinician sign-in
link) routed straight to the new "People & roles" screen purely by JWT
role; the list rendered all real users with the correct computed
`linked_summary` per role (a doctor's patient count, a patient's
assigned-doctor name, an attendant's linked patient, "System" for
admin) and `diagnosis` for patient rows; the search filter narrowed
correctly; **a user of all four roles (patient/doctor/attendant/admin)
was created through the real "Invite a person" form, and each one's
password was confirmed to actually work by logging in as that new user
immediately afterward** (same verification pattern the backend admin
router's original 2026-08-25 pass used) — all four also confirmed
present via a direct Postgres `SELECT`; **an existing user was edited
(name + language_preference) through the real "Edit person" form, and
the change was confirmed to persist via a direct Postgres `SELECT`**,
not just the UI's own "User updated." confirmation; a non-admin role
(patient) was confirmed to never reach the People screen at all —
logging in as a patient routed to the ordinary `PatientShell` exactly as
before, admin screens structurally unreachable — and a freshly-created
non-admin (doctor and patient) JWT was confirmed via curl to get a real
`403` from `GET`/`POST /admin/users` (`{"detail":"Not authorized for
this action"}`), matching the graceful `ApiException`-driven error
handling every other role in this app already uses (same `_ErrorState`
retry-button pattern as `PatientRosterScreen`/`AlertsScreen`). This
completes the admin role on Flutter — all three roles (patient/doctor/
admin) are now built and verified on this platform. Full narrative in
`context/decisions-log.md`.
