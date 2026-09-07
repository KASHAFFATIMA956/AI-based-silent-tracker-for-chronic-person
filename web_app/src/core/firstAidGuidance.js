// Fixed, citable first-aid guidance mapped to hard-flag conditions — a
// small, explicit, hand-authored mapping, NOT AI-generated per request
// (the only consumer is components/ChestPainFirstAidPanel.jsx). Scoped to
// exactly ONE condition this pass: suspected heart attack, i.e. the
// existing chest-pain hard flag in Backend/app/services/rules.py's
// HEART_FAILURE_RULES["hard_red_symptoms"] = {"Chest pain"}.
//
// The content below is paraphrased (not verbatim-copied) from real,
// citable American Heart Association public first-aid materials — see
// CHEST_PAIN_FIRST_AID.citation for the exact source pages. It is a fixed
// module-level constant, never regenerated or rephrased per request.
//
// PROTOTYPE — NOT clinically reviewed. See context/decisions-log.md and
// context/pre-deployment-checklist.md for what real clinical sign-off
// would need to cover before this is more than a hackathon demo feature.
// Mirrors mobile_app/lib/core/first_aid_guidance.dart (same wording, same
// source) — keep both in sync if this content ever changes.

export const CHEST_PAIN_FIRST_AID = {
  conditionKey: 'chest_pain',
  panelTitle: 'Suspected heart attack — first aid',
  primaryInstruction:
    "Call your local emergency number right away — even if you're not fully sure it's " +
    "a heart attack. Don't wait to see if the pain passes, and avoid driving to the " +
    'hospital yourself if you can help it — emergency responders can start treatment ' +
    'the moment they arrive.',
  checklistPrompt:
    'Before considering aspirin, confirm ALL four of the following are true. Leave a ' +
    'box unchecked if you\'re not sure — it will be treated the same as "no".',
  checklistItems: [
    'No known allergy to aspirin',
    'Not currently taking blood-thinning medicine (e.g. warfarin)',
    'No known bleeding disorder',
    "Patient is an adult, not a child or adolescent (risk of Reye's syndrome)",
  ],
  aspirinGuidance:
    'If all four are confirmed: chewing (not swallowing whole) one adult-strength, ' +
    'non-enteric-coated aspirin (about 162-325mg) while waiting for help can let it ' +
    'reach the bloodstream faster. If you reach an emergency dispatcher first, follow ' +
    'their advice on whether and how much to give. This is a secondary step only — ' +
    'never a substitute for calling for help.',
  suppressedNote:
    'Do not give aspirin unless you are sure it is safe. Call emergency services now, ' +
    'and tell the responders about the symptoms and about any allergies, medications ' +
    '(including blood thinners), or bleeding disorders the patient has.',
  disclaimer:
    'This is general guidance, not personal medical advice. It does not replace ' +
    'professional emergency care.',
  citation:
    'Paraphrased from the American Heart Association\'s public first-aid materials: ' +
    '"Warning Signs of a Heart Attack" ' +
    '(heart.org/en/health-topics/heart-attack/warning-signs-of-a-heart-attack) and the ' +
    '2024 AHA/American Red Cross Guidelines for First Aid, Part 8 — First Aid ' +
    '(cpr.heart.org/en/resuscitation-science/first-aid-guidelines/first-aid).',
}
