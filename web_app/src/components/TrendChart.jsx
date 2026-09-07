// A minimal hand-drawn SVG line chart — no charting library dependency, in
// the same spirit as the prototype's own hand-drawn SVG polylines
// (RozNoor.dc.html's d-detail Sleep/Weight cards) and mirroring
// mobile_app/lib/widgets/trend_chart.dart's CustomPainter equivalent.
// Renders the patient's actual recorded values over time, chronologically
// ordered by the caller.
//
// **No shaded baseline band** — a real backend-scope gap, not an
// oversight: the prototype's Sleep/Weight cards shade a "learned normal"
// band from baseline_history.baseline_min/max, but no endpoint exposes
// that table to a client (checked context/api-contracts.md in full before
// building — same conclusion the Flutter doctor build reached, see
// context/decisions-log.md). This plots raw recorded values instead — real
// trend data, just not a baseline band.
export function TrendChart({ points, lineColor, height = 120 }) {
  if (points.length < 2) {
    return (
      <div style={{ height, display: 'grid', placeItems: 'center', fontSize: 13, opacity: 0.55 }}>
        Not enough data yet for a trend line.
      </div>
    )
  }

  const width = 560
  const padding = 10
  const values = points.map((p) => p.value)
  const minVal = Math.min(...values)
  const maxVal = Math.max(...values)
  const range = Math.abs(maxVal - minVal) < 0.001 ? 1 : maxVal - minVal
  const w = width - padding * 2
  const h = height - padding * 2

  const coords = points.map((p, i) => {
    const x = padding + (w * i) / (points.length - 1)
    const y = padding + h - ((p.value - minVal) / range) * h
    return { x, y, point: p }
  })
  const linePoints = coords.map((c) => `${c.x},${c.y}`).join(' ')

  return (
    <svg viewBox={`0 0 ${width} ${height}`} style={{ width: '100%', height }}>
      <polyline points={linePoints} fill="none" stroke={lineColor} strokeWidth="1.75" strokeLinejoin="round" />
      {coords.map((c, i) => (
        <circle key={i} cx={c.x} cy={c.y} r="3.5" fill="var(--rn-surface)" stroke={lineColor} strokeWidth="1.75">
          <title>
            {new Date(c.point.timestamp).toLocaleDateString()}: {c.point.value}
          </title>
        </circle>
      ))}
    </svg>
  )
}
