// Small derived-value helpers for a PatientOut response — mirrors the
// getters on mobile_app/lib/models/patient_profile.dart (PatientProfile).
// Kept as plain functions here rather than a class since this app has no
// model layer (see context/decisions-log.md, "no codegen" note carried
// over from the Flutter app's own model-layer rationale).

export function baselineStageLabel(profile) {
  switch (profile?.baseline_stage) {
    case 'personalized':
      return 'Personalised pattern model'
    case 'learning':
      return 'Learning your pattern'
    default:
      return 'Collecting your first ranges'
  }
}

// medication_info is stored as one semicolon-separated free-text field
// (see context/schema.md); split for display as individual chips, matching
// the prototype's Medicines row.
export function medicationList(profile) {
  const raw = profile?.medication_info
  if (!raw || !raw.trim()) return []
  return raw
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean)
}
