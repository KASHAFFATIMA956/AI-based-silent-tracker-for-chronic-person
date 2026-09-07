import { RiskBadge } from '../../components/RiskBadge'
import { riskColor } from '../../core/riskColors'
import { usePatientData } from '../../state/PatientDataContext'

// GET /entries/{patient_id}/timeline — mirrors
// mobile_app/lib/screens/patient/timeline_screen.dart. Timeline data is
// already loaded/kept fresh by PatientDataContext (every submitEntry call
// refreshes it), so this screen just renders what's there.
export function TimelineScreen() {
  const { timeline, isLoading, loadError, refreshTimeline } = usePatientData()

  return (
    <div style={{ padding: '32px 40px', maxWidth: 880 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <h1 style={{ fontSize: 28 }}>My Timeline</h1>
        <button className="rn-btn rn-btn-ghost" onClick={refreshTimeline}>Refresh</button>
      </div>
      <p className="rn-muted" style={{ marginTop: 4, marginBottom: 24 }}>
        {timeline.length} entr{timeline.length === 1 ? 'y' : 'ies'} logged.
      </p>

      {isLoading && timeline.length === 0 && <p>Loading…</p>}
      {loadError && timeline.length === 0 && <p style={{ color: 'var(--rn-red)' }}>{loadError}</p>}
      {!isLoading && timeline.length === 0 && !loadError && (
        <p>No entries yet. Your first check-in will show up here.</p>
      )}

      <div>
        {timeline.map((entry) => (
          <TimelineRow key={entry.id} entry={entry} />
        ))}
      </div>
    </div>
  )
}

function TimelineRow({ entry }) {
  const color = riskColor(entry.risk_result?.risk_level)
  const date = new Date(entry.timestamp)
  const quote =
    entry.entry_type === 'voice'
      ? entry.raw_transcript || ''
      : `Quick check-in — medicine ${entry.medicine_status === 'taken' ? 'taken' : 'missed'}`

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '72px 1fr', gap: 18, padding: '18px 0', borderBottom: '1px solid var(--rn-divider)' }}>
      <div style={{ textAlign: 'right' }}>
        <div style={{ fontSize: 19, fontWeight: 600, fontFamily: 'Space Grotesk, sans-serif' }}>{date.getDate()}</div>
        <div className="rn-muted" style={{ fontSize: 11, textTransform: 'uppercase' }}>
          {date.toLocaleString(undefined, { month: 'short' })}
        </div>
      </div>
      <div style={{ borderLeft: `2px solid ${color}`, paddingLeft: 16, display: 'flex', flexDirection: 'column', gap: 6 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 16, fontWeight: 600 }}>{entry.entry_type === 'voice' ? 'Voice entry' : 'Quick check-in'}</span>
          <RiskBadge level={entry.risk_result?.risk_level} />
          <span className="rn-muted" style={{ fontSize: 12, marginLeft: 'auto' }}>
            {date.toLocaleString(undefined, { hour: 'numeric', minute: '2-digit' })}
          </span>
        </div>
        {quote && <p style={{ margin: 0, fontSize: 14, opacity: 0.85 }}>{quote}</p>}
        <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', fontSize: 12, opacity: 0.6 }}>
          {entry.sleep_value != null && <span>Sleep {Number(entry.sleep_value).toFixed(1)}h</span>}
          {entry.energy_value != null && <span>Energy {Number(entry.energy_value).toFixed(0)}/5</span>}
          {entry.weight_value != null && <span>Weight {Number(entry.weight_value).toFixed(1)}kg</span>}
          {/* Added 2026-09-07 — persisted-only fields, see
              context/api-contracts.md. */}
          {entry.systolic_bp != null && entry.diastolic_bp != null && (
            <span>BP {entry.systolic_bp}/{entry.diastolic_bp}</span>
          )}
          {entry.blood_sugar_mg_dl != null && <span>Sugar {entry.blood_sugar_mg_dl} mg/dL</span>}
          <span>Medicine {entry.medicine_status === 'taken' ? 'taken' : 'missed'}</span>
        </div>
      </div>
    </div>
  )
}
