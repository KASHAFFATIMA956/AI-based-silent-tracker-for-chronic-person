# Schema — as implemented

Source of truth: `Backend/app/models/*.py` (SQLAlchemy 2.0 declarative), migrated via
`Backend/alembic/versions/a2d9108573f3_initial_schema_11_tables.py` (initial 11 tables),
`3973a8111b8e_add_entries_weight_value.py` (adds `entries.weight_value`, 2026-08-24),
and `4674989821f7_add_entries_audio_file_path_and_ai_.py` (adds `entries.audio_file_path`
+ `ai_results.acoustic_features`, 2026-08-25 — see below and [[decisions-log]]).
Matches `docs/RozNoor_Database_Schema_and_Deployment_Plan.docx` section 4 exactly except
for two confirmed deviations: the table count is **11**, not the "twelve" the doc's
header claims, and `entries` has one column (`weight_value`) the doc's original list
didn't — see [[decisions-log]] for why on both. The AI layer pass (2026-08-24, see
[[progress]]) added no schema/migration changes — `ai_results` already existed with
exactly the columns the AI layer needed. The doctor & admin routers pass (2026-08-25,
see [[progress]]) also added **no schema/migration changes** — every table/column those
routers needed (`alerts`, `doctor_notes`, `users`) already existed. One explicit
non-change: the admin "People & roles" screen's `status` (Active/Invited) badge has no
backing column in `users` and none was added — see [[decisions-log]]. The Flutter
patient-app pass (2026-08-25, see [[progress]]) likewise added **no schema/migration
changes** — its three backend additions (`patient_id` on `GET /auth/me`, extra
`PatientOut` fields, `GET /patients/{id}/symptom-checklist`) only expose columns/logic
that already existed; see [[api-contracts]] and [[decisions-log]]. The React web app
pass (2026-08-29, see [[progress]]) added **no backend changes at all** — same
endpoints reused verbatim, verified against the exact contracts already documented
here and in [[api-contracts]]. The React web app's doctor-role pass (2026-08-29,
later same day, see [[progress]]) likewise added **no backend/schema changes at
all** — this completes the doctor role on both platforms with zero schema drift
across every pass that touched it. The Flutter admin-role pass (2026-08-29,
later same day, see [[progress]]) also added **no schema/migration changes** —
`GET/POST /admin/users` and `PATCH /admin/users/{id}` were already complete and
verified from the 2026-08-25 doctor & admin routers pass; this session only
built the Flutter screens against them. This completes all three roles on
Flutter with zero schema drift across every pass. The React web app's
admin-role pass (2026-08-29, final session, see [[progress]]) likewise
added **no schema/migration changes at all** — same two endpoints reused
verbatim. This completes all three roles on BOTH platforms with zero
schema drift across every single pass that ever touched this project.

Verified end-to-end against a throwaway local Postgres 16 container: `alembic upgrade
head` applied cleanly, `seed.py` populated all 11 tables with no FK errors, and
re-running `seed.py` is idempotent (clears + re-inserts to identical row counts).

## Enums (`app/models/enums.py`)
| Postgres type | Python enum | Values |
|---|---|---|
| `user_role` | `UserRole` | patient, attendant, doctor, admin |
| `language_preference` | `LanguagePreference` | english, roman_urdu |
| `baseline_stage` | `BaselineStage` | cold_start, learning, personalized |
| `entry_type` | `EntryType` | voice, quick |
| `medicine_status` | `MedicineStatus` | taken, missed |
| `risk_level` | `RiskLevel` | Green, Yellow, Orange, Red (capitalized — matches doc/UI literal labels) |
| `risk_source` | `RiskSource` | ai, rule, merged |

`risk_level` is shared (same Postgres enum type) between `risk_results.risk_level` and
`alerts.risk_level`.

## Tables

### users
Shared login table for all roles.
| Column | Type | Notes |
|---|---|---|
| id | PK int | |
| name | text | |
| role | user_role | |
| phone_or_email | text | unique, login identifier |
| password_hash | text | real bcrypt hash (`app.core.security.hash_password`) as of 2026-08-24 |
| language_preference | language_preference | default english |
| created_at | timestamp | server default now() |

### patients
One row per patient.
| Column | Type | Notes |
|---|---|---|
| id | PK int | |
| user_id | FK users, nullable | |
| attendant_user_id | FK users, nullable | expected role=attendant, not DB-enforced |
| age | int, nullable | |
| mr_number | text, nullable | |
| diagnosis | text, nullable | free text, not enum |
| assigned_doctor_id | FK users, nullable | expected role=doctor, not DB-enforced |
| emergency_contact_name | text, nullable | |
| emergency_contact_phone | text, nullable | |
| medication_info | text, nullable | free text (see [[decisions-log]] — no separate medications table) |
| baseline_stage | baseline_stage | default cold_start |
| day_count | int | default 0, drives baseline_stage |
| created_at | timestamp | |

### entries
Every check-in, voice or quick.
| Column | Type | Notes |
|---|---|---|
| id | PK int | |
| patient_id | FK patients | |
| entry_type | entry_type | |
| timestamp | timestamp | not nullable — used for ordering |
| raw_transcript | text, nullable | voice only |
| transcript_translation | text, nullable | voice only |
| sleep_value | numeric, nullable | quick only — seeded in hours |
| energy_value | numeric, nullable | quick only — seeded 1-5 |
| mood_value | numeric, nullable | quick only — seeded 1-5 |
| appetite_value | numeric, nullable | quick only — seeded 1-5 |
| mobility_value | numeric, nullable | quick only — seeded 1-5 |
| weight_value | numeric, nullable | kg; NOT gated to entry_type; added 2026-08-24 |
| audio_file_path | text, nullable | voice only; local-disk relative path; added 2026-08-25 |
| medicine_status | medicine_status | |
| created_at | timestamp | |

**`audio_file_path` added 2026-08-25** (acoustic-analysis pass) — set by a SEPARATE
call, `POST /entries/{id}/audio`, never by `POST /entries` itself (which stays
unchanged JSON-only — see [[decisions-log]] for the architecture rationale). Local
disk storage under `settings.audio_storage_dir` (default `audio_storage/`,
gitignored) is an explicit **hackathon-scope shortcut** — not S3/cloud storage, not
multi-instance safe — flagged in [[decisions-log]]. Never exposed to API clients
directly; `EntryOut.has_audio` (a boolean) is what clients see instead. Migration:
`alembic/versions/4674989821f7_add_entries_audio_file_path_and_ai_.py` (same migration
also adds `ai_results.acoustic_features` below — one column-diff each, autogenerated
cleanly against the existing schema).

Scale for the numeric quick-checkin fields (1-5 for energy/mood/appetite/mobility,
hours for sleep) is confirmed/locked per the user and the now-available
`docs/RozNoor_Mobile_UI_Field_Requirements.docx` — see [[decisions-log]], and enforced
at the API boundary in `app/schemas/entry.py`.

**`weight_value` added 2026-08-24** — a real schema change, confirmed with the user
first (see [[decisions-log]]). The schema doc's original column list didn't include
it, but the project doc/prototype both treat weight as a core heart-failure safety
signal (the "2kg in three days" clinician-set threshold), so this was a genuine gap,
not an intentional omission. Migration:
`alembic/versions/3973a8111b8e_add_entries_weight_value.py`. Now wired into the
heart-failure hard red-flag rule (`app/services/rules.py`) and tracked as its own
`baseline_history` metric (`app/services/baseline.py`) — see [[decisions-log]] for
both. Bounds enforced at the API boundary: 0-300kg (a sanity check, not a clinical
range). Not gated to `entry_type` — a weight-only reading is a valid "quick" entry on
its own (a morning weigh-in with no sliders filled in).

### entry_symptoms
M:N join, entries <-> symptom_checklist_options.
| Column | Type |
|---|---|
| id | PK int |
| entry_id | FK entries |
| symptom_id | FK symptom_checklist_options |

### symptom_checklist_options
Lookup table, varies by diagnosis (free text, not enum).
| Column | Type |
|---|---|
| id | PK int |
| diagnosis | text |
| symptom_name | text |

Seeded: 6 heart-failure options (verbatim from the UI prototype), 6 post-surgical
options (invented for seed realism — see [[decisions-log]]).

### ai_results
1:1 with entries. As of 2026-08-24, populated for real by `app.services.ai` — only for
**voice** entries where the Claude API call actually succeeds (no row is written on a
quick entry, a missing/invalid API key, or any API failure/timeout). See
[[decisions-log]] for the full merge design.
| Column | Type | Notes |
|---|---|---|
| id | PK int | |
| entry_id | FK entries, unique | |
| extracted_symptom_tags | JSONB, nullable | list: matched checklist symptom names + free-text tags (e.g. `["Breathlessness", "Ankle swelling", "onset: since this morning", "fatigue up"]`) |
| deviation_deltas | JSONB, nullable | dict keyed by metric, computed in plain Python (not by Claude) from `baseline_history` — deterministic, never hallucinated |
| acoustic_features | JSONB, nullable | signal-processing output, added 2026-08-25 — see below |
| created_at | timestamp | |

**`acoustic_features` added 2026-08-25** (acoustic-analysis pass) — set by
`POST /entries/{id}/audio` (`app/services/audio_analysis.py`, numpy + a system
`ffmpeg` subprocess for decoding — NOT librosa, see [[decisions-log]] for the
mid-build pivot; explicitly **NOT a machine-learning model** — no training data
exists for this project). Populates this same row a voice entry's Claude symptom
extraction may
already have created (or creates a fresh row if AI extraction didn't run/succeed for
that entry) — one `ai_results` row per entry regardless of how many of its columns get
filled in, by which step. Dict shape: `{duration_sec, pause_ratio, num_pauses,
speaking_rate_segments_per_min, energy_rms_mean, energy_rms_variance, energy_cv,
pitch_mean_hz, pitch_variability_hz, possible_fatigue_or_breathlessness}` — full field
citations in `app/services/audio_analysis.py`'s docstring. Every threshold behind
`possible_fatigue_or_breathlessness` is a Claude Code proposal needing clinician-
equivalent review, same as the rule-engine thresholds — see [[decisions-log]].

### risk_results
1:1 with entries. Kept separate from ai_results so the rule engine can populate this
even when Claude API is down (`source='rule'`). `source` is now genuinely `'merged'`
in practice (not just `'rule'`) — see [[decisions-log]] for exactly when.
| Column | Type | Notes |
|---|---|---|
| id | PK int | |
| entry_id | FK entries, unique | |
| risk_level | risk_level | |
| risk_title | text, nullable | |
| risk_message | text, nullable | |
| reasoning | text, nullable | |
| source | risk_source | |
| created_at | timestamp | |

### baseline_history
One row per patient **per metric**.
| Column | Type |
|---|---|
| id | PK int |
| patient_id | FK patients |
| metric | text (e.g. "sleep", "weight", "energy") |
| baseline_min | numeric |
| baseline_max | numeric |
| last_updated | timestamp, onupdate now() |

As of 2026-08-24, `app.services.baseline.update_baseline_after_entry` (called from
`POST /entries`) recomputes these rows for real from a patient's actual `entries`
history — sleep/energy/mood/appetite/mobility/**weight** (weight added same day as
`entries.weight_value`). Note weight's band is for charting/trend purposes only; the
safety-relevant direction (a rise) is handled separately by
`app.services.rules`'s dedicated red-flag check, not by comparing against this band's
lower bound the way the other metrics are. See [[decisions-log]] for the baseline
formula (proposed, needs review) and the seed-data-gets-overwritten interaction.

### alerts
Drives the doctor Alerts Panel.
| Column | Type | Notes |
|---|---|---|
| id | PK int | |
| patient_id | FK patients | |
| entry_id | FK entries, nullable | |
| risk_level | risk_level | |
| alert_text | text | |
| source_rule | text, nullable | |
| reviewed | boolean | default false |
| created_at | timestamp | |

As of 2026-08-25, `reviewed` is flipped to `true` for real by
`POST /alerts/{alert_id}/review` (`app/routers/doctors.py`) — previously only
seed-populated. `GET /doctors/{doctor_id}/alerts` reads this table filtered to the
doctor's own patients, optionally by `?reviewed=`.

### doctor_notes
| Column | Type |
|---|---|
| id | PK int |
| patient_id | FK patients |
| doctor_id | FK users (expected role=doctor, not DB-enforced) |
| note_text | text |
| created_at | timestamp |

As of 2026-08-25, populated for real by `POST /patients/{patient_id}/notes`
(`app/routers/patients.py`), doctor/admin only. `doctor_id` is the authoring
*user's* id, which can legitimately be an admin's id when an admin authors a note
(mirrors the existing "not DB-enforced" convention on `assigned_doctor_id` — see
[[decisions-log]]). `GET /patients/{patient_id}/notes` lists them newest-first,
same RBAC.

### weekly_digests
Stored table (not computed live) — see [[decisions-log]] for why this was picked over
live computation for now.
| Column | Type |
|---|---|
| id | PK int |
| patient_id | FK patients |
| period_start | date |
| period_end | date |
| summary_text | text |
| created_at | timestamp |

## Seed data (`Backend/seed.py`)
Realistic dataset pulled from `UI Inspo/.../RozNoor.dc.html`:
- **Doctors**: Dr. Ayesha Farooq (Cardiology), Dr. Hamza Iqbal (Post-surgical)
- **Admin**: Sadia Kamran
- **Attendant**: Imran Zubair (linked to Zubaida Bibi)
- **Patients**: Ghulam Rasool (MR 40-1188, Red/chest pain), Zubaida Bibi (MR 40-2291,
  Orange/weight+sleep+energy), Naseem Akhtar (MR 40-2010, Orange/missed doses),
  Bashir Ahmed (MR 40-1974, Yellow/sleep), Farida Yousuf (MR 40-2255, Yellow/appetite),
  Mukhtar Ali (MR 40-1902, Green/stable) — matching the prototype roster's names, MR
  numbers, diagnoses, day counts, and risk levels exactly.
- 19 entries, 4 with linked symptoms + AI extraction, 19 risk_results, 5 alerts, 10
  baseline_history rows, 3 doctor notes, 1 weekly digest.
- Zubaida Bibi's 6 entries carry a weight trajectory (62.0 -> 62.0 -> 62.6 -> 63.2 ->
  63.8 -> 64.4 kg) reproducing the "+2.4 kg / 5 days" figure already referenced in her
  alert/reasoning text. Ghulam Rasool and Mukhtar Ali carry stable weight trends (no
  red-flag) as a contrast case. Naseem/Bashir/Farida have no weight_value seeded (the
  weight red-flag only applies to the heart_failure ruleset).
- Re-running `python seed.py` clears and re-seeds — safe, deterministic, dev-only.
