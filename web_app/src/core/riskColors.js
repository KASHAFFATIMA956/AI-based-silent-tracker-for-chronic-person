// Mirrors mobile_app/lib/core/theme.dart's RnColors.forRiskLevel — same
// four risk-level inks, fixed regardless of Paper/Nocturne theme (see
// theme.css's comment on why risk colors aren't duplicated per-theme).
const RISK_COLORS = {
  Green: 'var(--rn-green)',
  Yellow: 'var(--rn-amber)',
  Orange: 'var(--rn-coral)',
  Red: 'var(--rn-red)',
}

export function riskColor(level) {
  return RISK_COLORS[level] ?? 'var(--rn-neutral-500)'
}
