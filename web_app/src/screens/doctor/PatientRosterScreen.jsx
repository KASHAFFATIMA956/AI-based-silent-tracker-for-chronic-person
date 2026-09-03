import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { RiskBadge } from '../../components/RiskBadge'
import { riskColor } from '../../core/riskColors'
import { useDoctorData } from '../../state/DoctorDataContext'

// GET /doctors/{doctor_id}/patients — the doctor home / patient roster.
// Content/layout source: the prototype's d-patients screen
// (RozNoor.dc.html) — a searchable table, unlike mobile's stacked cards
// (a web app has the table-column room a phone doesn't) — see
// context/conventions.md. "N monitored · N need attention" count pattern
// mirrors mobile_app's patient_roster_screen.dart exactly.
export function PatientRosterScreen() {
  const data = useDoctorData()
  const navigate = useNavigate()
  const [query, setQuery] = useState('')

  const needsAttention = data.roster.filter((p) => p.latest_risk_level && p.latest_risk_level !== 'Green').length

  const q = query.trim().toLowerCase()
  const filtered = q
    ? data.roster.filter(
        (p) => p.name.toLowerCase().includes(q) || (p.mr_number ?? '').toLowerCase().includes(q),
      )
    : data.roster

  return (
    <div style={{ padding: '32px 40px', maxWidth: 1080 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 18, flexWrap: 'wrap', marginBottom: 20 }}>
        <h1 style={{ fontSize: 28 }}>Patients</h1>
        <span className="rn-muted" style={{ fontSize: 13 }}>
          {data.roster.length} monitored · {needsAttention} need attention
        </span>
      </div>

      <input
        className="rn-input"
        style={{ maxWidth: 340, marginBottom: 20 }}
        placeholder="Search name or MR number"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />

      {data.isLoading && data.roster.length === 0 && <p>Loading…</p>}
      {data.loadError && data.roster.length === 0 && (
        <p style={{ color: 'var(--rn-red)' }}>{data.loadError}</p>
      )}
      {!data.isLoading && !data.loadError && filtered.length === 0 && (
        <p className="rn-muted">
          {data.roster.length === 0 ? 'No patients assigned yet.' : 'No patients match this search.'}
        </p>
      )}

      {filtered.length > 0 && (
        <div style={{ overflowX: 'auto' }}>
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: '1.6fr 1.3fr 0.7fr 1fr 1.6fr 0.8fr',
              gap: 0,
              fontSize: 11,
              letterSpacing: '0.08em',
              textTransform: 'uppercase',
              opacity: 0.6,
              borderBottom: '1px solid var(--rn-divider)',
              padding: '0 8px 9px',
              minWidth: 760,
            }}
          >
            <span>Patient</span>
            <span>Diagnosis</span>
            <span>Day</span>
            <span>Last entry</span>
            <span>Reasoning</span>
            <span style={{ textAlign: 'right' }}>Status</span>
          </div>
          {filtered.map((p) => (
            <RosterRow key={p.patient_id} patient={p} onOpen={() => navigate(`/roster/${p.patient_id}`)} />
          ))}
        </div>
      )}
    </div>
  )
}

function RosterRow({ patient, onOpen }) {
  const color = riskColor(patient.latest_risk_level)
  const lastEntry = patient.last_entry_timestamp
    ? new Date(patient.last_entry_timestamp).toLocaleString(undefined, {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })
    : 'No entries yet'

  return (
    <div
      onClick={onOpen}
      style={{
        display: 'grid',
        gridTemplateColumns: '1.6fr 1.3fr 0.7fr 1fr 1.6fr 0.8fr',
        alignItems: 'center',
        gap: 0,
        padding: '14px 8px',
        borderBottom: '1px solid var(--rn-divider)',
        borderLeft: `2px solid ${color}`,
        cursor: 'pointer',
        fontSize: 14,
        minWidth: 760,
      }}
    >
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
        <b style={{ fontFamily: 'Space Grotesk, sans-serif', fontSize: 17, fontWeight: 600 }}>{patient.name}</b>
        <span className="rn-muted" style={{ fontSize: 12 }}>
          {patient.mr_number ?? '—'}
          {patient.age != null ? ` · ${patient.age}` : ''}
        </span>
      </span>
      <span style={{ opacity: 0.8 }}>{patient.diagnosis ?? 'No diagnosis on file'}</span>
      <span style={{ opacity: 0.8, fontVariantNumeric: 'tabular-nums' }}>{patient.day_count}</span>
      <span style={{ opacity: 0.8 }}>{lastEntry}</span>
      <span style={{ opacity: 0.85, fontSize: 13 }}>{patient.latest_reasoning ?? '—'}</span>
      <span style={{ textAlign: 'right' }}>
        <RiskBadge level={patient.latest_risk_level} />
      </span>
    </div>
  )
}
