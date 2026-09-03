import { riskColor } from '../core/riskColors'

// The small pill tag used everywhere a risk_level ("Green"/"Yellow"/
// "Orange"/"Red") needs to show up as a label — mirrors
// mobile_app/lib/widgets/risk_badge.dart's RiskBadge.
export function RiskBadge({ level }) {
  const color = riskColor(level)
  return (
    <span className="rn-tag" style={{ color, borderColor: color }}>
      {level ?? 'Unknown'}
    </span>
  )
}

// The small filled dot used next to "Today's status" — mirrors RiskDot.
export function RiskDot({ level, size = 11 }) {
  return (
    <span
      className="rn-dot"
      style={{ width: size, height: size, background: riskColor(level) }}
    />
  )
}
