import { useState } from 'react'
import { CHEST_PAIN_FIRST_AID as guidance } from '../core/firstAidGuidance'

// Shown on the Result screen ONLY when the just-submitted entry's
// risk_result.risk_level is Red AND its symptom_names includes the
// "Chest pain" hard-flag symptom (the same literal string
// app/services/rules.py's HEART_FAILURE_RULES["hard_red_symptoms"] checks
// against) — the caller (ResultScreen.jsx) decides when to render this;
// it is wired in at the display layer, not inside the rule engine, per
// the task's explicit instruction. Mirrors
// mobile_app/lib/widgets/chest_pain_first_aid_panel.dart.
//
// The contraindication checklist below must be actively confirmed (all
// four boxes checked) before the aspirin-specific guidance is revealed.
// Leaving any box unchecked — including "not sure" — keeps the aspirin
// guidance suppressed and shows only the call-for-help fallback.
//
// PROTOTYPE — NOT clinically reviewed. See
// src/core/firstAidGuidance.js's own doc comment and
// context/pre-deployment-checklist.md before any non-demo use.
export function ChestPainFirstAidPanel() {
  const [confirmed, setConfirmed] = useState(() => guidance.checklistItems.map(() => false))
  const allConfirmed = confirmed.every(Boolean)

  const toggle = (i) => setConfirmed((prev) => prev.map((v, idx) => (idx === i ? !v : v)))

  return (
    <div
      className="rn-card"
      style={{ marginTop: 16, padding: 20, borderColor: 'var(--rn-red)', borderWidth: 2 }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <span aria-hidden="true" style={{ fontSize: 20 }}>🚑</span>
        <span style={{ fontSize: 16, fontWeight: 700, color: 'var(--rn-red)' }}>{guidance.panelTitle}</span>
      </div>

      {/* Instruction #1 — always visible, most prominent, shown
          regardless of the checklist below. */}
      <div
        style={{
          marginTop: 12,
          padding: 12,
          borderRadius: 10,
          background: 'color-mix(in srgb, var(--rn-red) 8%, transparent)',
          fontSize: 15,
          fontWeight: 600,
          lineHeight: 1.45,
        }}
      >
        {guidance.primaryInstruction}
      </div>

      <p style={{ marginTop: 16, marginBottom: 4, fontSize: 13, fontWeight: 600, opacity: 0.85 }}>
        {guidance.checklistPrompt}
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {guidance.checklistItems.map((item, i) => (
          <label key={item} style={{ display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: 14, cursor: 'pointer' }}>
            <input
              type="checkbox"
              checked={confirmed[i]}
              onChange={() => toggle(i)}
              style={{ marginTop: 3 }}
            />
            <span>{item}</span>
          </label>
        ))}
      </div>

      {allConfirmed ? (
        <div
          style={{
            marginTop: 12,
            padding: 12,
            borderRadius: 10,
            background: 'var(--rn-accent-100)',
            border: '1px solid var(--rn-accent-300)',
          }}
        >
          <div style={{ fontSize: 10, letterSpacing: 1, fontWeight: 700, color: 'var(--rn-accent-dark)' }}>
            SECONDARY — ONLY IF SAFE
          </div>
          <p style={{ marginTop: 6, marginBottom: 0, fontSize: 13.5, lineHeight: 1.45 }}>
            {guidance.aspirinGuidance}
          </p>
        </div>
      ) : (
        <div
          style={{
            marginTop: 12,
            padding: 12,
            borderRadius: 10,
            background: 'color-mix(in srgb, var(--rn-text) 6%, transparent)',
          }}
        >
          <p style={{ margin: 0, fontSize: 13.5, lineHeight: 1.45, opacity: 0.85 }}>
            {guidance.suppressedNote}
          </p>
        </div>
      )}

      <div style={{ marginTop: 14, padding: 10, borderRadius: 8, border: '1px solid var(--rn-divider)' }}>
        <p style={{ margin: 0, fontSize: 12.5, fontWeight: 600, fontStyle: 'italic' }}>{guidance.disclaimer}</p>
      </div>
      <p style={{ marginTop: 8, fontSize: 10.5, opacity: 0.55 }}>{guidance.citation}</p>
    </div>
  )
}
