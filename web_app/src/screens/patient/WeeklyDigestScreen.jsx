import { riskColor } from '../../core/riskColors'
import { usePatientData } from '../../state/PatientDataContext'

// "Weekly Trends" — same approach as mobile_app's weekly_digest_screen.dart:
// there is no dedicated weekly-digest backend endpoint (`weekly_digests` is
// a stored table with no route reading/writing it — see
// context/progress.md), so this screen computes its own week-over-week
// view entirely from real GET /entries/{id}/timeline data already loaded.
// Still real data, just aggregated client-side instead of fabricated —
// same computation shape as the Flutter screen, ported to JS.
export function WeeklyDigestScreen() {
  const { timeline } = usePatientData()

  if (timeline.length === 0) {
    return (
      <div style={{ padding: '32px 40px' }}>
        <p>No entries yet — trends will appear once you have a week of check-ins.</p>
      </div>
    )
  }

  const digest = computeDigest(timeline)

  return (
    <div style={{ padding: '32px 40px', maxWidth: 900 }}>
      <span className="rn-kicker">{digest.rangeLabel}</span>
      <h1 style={{ fontSize: 28, marginTop: 6 }}>What quietly changed</h1>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 14, marginTop: 18 }}>
        {digest.insights.map((i, idx) => (
          <div key={idx} className="rn-card" style={{ padding: 20, borderLeft: `3px solid ${i.color}` }}>
            <span className="rn-kicker" style={{ color: i.color }}>{i.kicker.toUpperCase()}</span>
            <p style={{ margin: '6px 0 0', fontSize: 18, fontWeight: 600, fontFamily: 'Space Grotesk, sans-serif' }}>{i.text}</p>
          </div>
        ))}
      </div>

      <div className="rn-card" style={{ marginTop: 18, padding: 22 }}>
        <span className="rn-kicker">SLEEP, LAST 7 NIGHTS</span>
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8, height: 130, marginTop: 14 }}>
          {digest.sleepBars.map((b, idx) => (
            <div key={idx} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-end', gap: 4 }}>
              <span style={{ fontSize: 11 }}>{b.value == null ? '—' : b.value.toFixed(1)}</span>
              <div style={{ width: '100%', height: (b.value ?? 0) * 10, background: 'var(--rn-accent-300)', border: '1px solid var(--rn-accent)', borderRadius: '3px 3px 0 0' }} />
              <span style={{ fontSize: 10 }}>{b.label}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="rn-card" style={{ marginTop: 16, padding: 22, borderColor: 'var(--rn-accent-300)' }}>
        <span className="rn-kicker">VS LAST WEEK</span>
        <div style={{ display: 'flex', gap: 24, flexWrap: 'wrap', marginTop: 12 }}>
          {digest.changed.map((c, idx) => (
            <div key={idx} style={{ minWidth: 120 }}>
              <div style={{ fontSize: 21, fontWeight: 600, color: c.color, fontFamily: 'Space Grotesk, sans-serif' }}>{c.value}</div>
              <div className="rn-muted" style={{ fontSize: 12 }}>{c.label}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function computeDigest(timeline) {
  const now = new Date()
  const weekStart = addDays(now, -6)
  const prevWeekStart = addDays(now, -13)

  const inRange = (ts, start, end) => {
    const t = new Date(ts)
    return t >= start && t <= end
  }

  const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate())
  const thisWeek = timeline.filter((e) => inRange(e.timestamp, startOfDay(weekStart), now))
  const lastWeek = timeline.filter((e) => inRange(e.timestamp, startOfDay(prevWeekStart), startOfDay(weekStart)))

  const bars = []
  for (let i = 6; i >= 0; i--) {
    const day = addDays(now, -i)
    const match = thisWeek.find((e) => {
      const t = new Date(e.timestamp)
      return t.getFullYear() === day.getFullYear() && t.getMonth() === day.getMonth() && t.getDate() === day.getDate() && e.sleep_value != null
    })
    bars.push({ label: day.toLocaleString(undefined, { weekday: 'short' })[0], value: match ? Number(match.sleep_value) : null })
  }

  const avg = (values) => {
    const v = values.filter((x) => x != null).map(Number)
    if (v.length === 0) return null
    return v.reduce((a, b) => a + b, 0) / v.length
  }

  const sleepAvgThis = avg(thisWeek.map((e) => e.sleep_value))
  const sleepAvgLast = avg(lastWeek.map((e) => e.sleep_value))
  const energyAvgThis = avg(thisWeek.map((e) => e.energy_value))

  const adherencePct = (entries) => {
    if (entries.length === 0) return 0
    const taken = entries.filter((e) => e.medicine_status === 'taken').length
    return Math.round((taken / entries.length) * 100)
  }
  const adherenceThis = adherencePct(thisWeek)
  const adherenceLast = adherencePct(lastWeek)

  const delta = (a, b, unit = '') => {
    if (a == null || b == null) return '—'
    const d = a - b
    return `${d >= 0 ? '+' : ''}${d.toFixed(1)}${unit}`
  }

  const changed = [
    { value: sleepAvgThis == null ? '—' : `${sleepAvgThis.toFixed(1)}h`, label: 'Avg sleep this week', color: 'var(--rn-accent-dark)' },
    {
      value: delta(sleepAvgThis, sleepAvgLast, 'h'),
      label: 'Change vs last week',
      color: (sleepAvgThis ?? 0) < (sleepAvgLast ?? 999) ? 'var(--rn-amber)' : 'var(--rn-green)',
    },
    { value: energyAvgThis == null ? '—' : energyAvgThis.toFixed(1), label: 'Avg energy (1-5)', color: 'var(--rn-accent-dark)' },
    { value: `${adherenceThis}%`, label: 'Medicine adherence', color: adherenceThis >= adherenceLast ? 'var(--rn-green)' : 'var(--rn-amber)' },
  ]

  const insights = []
  const worstThisWeek = thisWeek.filter((e) => e.risk_result && e.risk_result.risk_level !== 'Green')
  if (worstThisWeek.length > 0) {
    insights.push({
      kicker: `${worstThisWeek.length} entr${worstThisWeek.length === 1 ? 'y' : 'ies'} flagged`,
      text: `This week had ${worstThisWeek.length} entr${worstThisWeek.length === 1 ? 'y' : 'ies'} above your usual pattern.`,
      color: riskColor(worstThisWeek[0].risk_result.risk_level),
    })
  }
  if (sleepAvgThis != null && sleepAvgLast != null && sleepAvgThis < sleepAvgLast - 0.5) {
    insights.push({
      kicker: 'Sleep',
      text: `Sleep averaged ${sleepAvgThis.toFixed(1)}h this week, down from ${sleepAvgLast.toFixed(1)}h last week.`,
      color: 'var(--rn-amber)',
    })
  }
  if (adherenceThis < 100 && thisWeek.length > 0) {
    insights.push({
      kicker: 'Medicine',
      text: `Medicine was taken on ${adherenceThis}% of logged days this week.`,
      color: adherenceThis < 80 ? 'var(--rn-coral)' : 'var(--rn-accent)',
    })
  }
  if (insights.length === 0) {
    insights.push({ kicker: 'Stable week', text: 'Nothing stood out this week — everything stayed close to your usual pattern.', color: 'var(--rn-green)' })
  }

  const fmt = (d) => d.toLocaleString(undefined, { day: 'numeric', month: 'short' })
  return { rangeLabel: `${fmt(weekStart)} – ${fmt(now)}`, sleepBars: bars, changed, insights }
}

function addDays(date, days) {
  const d = new Date(date)
  d.setDate(d.getDate() + days)
  return d
}
