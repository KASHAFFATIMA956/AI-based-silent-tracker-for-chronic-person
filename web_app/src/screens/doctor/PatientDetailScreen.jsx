import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { RiskBadge } from '../../components/RiskBadge'
import { TrendChart } from '../../components/TrendChart'
import { ApiException } from '../../core/apiClient'
import { riskColor } from '../../core/riskColors'
import { useDoctorData } from '../../state/DoctorDataContext'

// Full patient detail for a doctor: check-in history/timeline (reusing the
// same GET /entries/{patient_id}/timeline the patient app itself calls), a
// raw-value trend chart per numeric metric, alert history, and doctor notes
// (view existing + add new). Content/layout source: the prototype's
// d-detail screen (RozNoor.dc.html) — see context/conventions.md.
//
// **On "baseline trend"**: no endpoint exposes baseline_history's min/max
// bands (see context/api-contracts.md), so — same as the Flutter build —
// TrendChart plots actual recorded values over time rather than the
// prototype's shaded "learned normal" band. See context/decisions-log.md.
export function PatientDetailScreen() {
  const { patientId } = useParams()
  const id = Number(patientId)
  const navigate = useNavigate()
  const data = useDoctorData()

  useEffect(() => {
    data.loadPatientDetail(id)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id])

  const profile = data.selectedPatient
  const timeline = data.selectedTimeline // newest first
  const chronological = [...timeline].reverse()
  const notes = data.selectedNotes
  const alertHistory = data.alerts.filter((a) => a.patient_id === id)
  const latestRisk = timeline.length > 0 ? timeline[0].risk_result?.risk_level : null

  // PatientOut (GET /patients/{id}) has no "name" field for the patient
  // themselves (see context/api-contracts.md) — only assigned_doctor_name/
  // attendant_name are exposed. mobile_app's Flutter build sidesteps this
  // by passing the name in directly from the roster tap (a Dart
  // constructor arg); this web build has no equivalent of that for a
  // route reached by URL, so it's looked up from data already loaded in
  // DoctorDataContext instead — the roster row (or, if opened from an
  // alert instead of the roster, the alert row) both already carry
  // patient_name.
  const rosterMatch = data.roster.find((p) => p.patient_id === id)
  const alertMatch = data.alerts.find((a) => a.patient_id === id)
  const patientName = rosterMatch?.name ?? alertMatch?.patient_name ?? `Patient #${id}`

  const weightPoints = chronological
    .filter((e) => e.weight_value != null)
    .map((e) => ({ timestamp: e.timestamp, value: Number(e.weight_value) }))
  const sleepPoints = chronological
    .filter((e) => e.sleep_value != null)
    .map((e) => ({ timestamp: e.timestamp, value: Number(e.sleep_value) }))

  if (data.isLoadingDetail && !profile) {
    return <div style={{ padding: '32px 40px' }}>Loading…</div>
  }

  if (data.detailError && !profile) {
    return (
      <div style={{ padding: '32px 40px' }}>
        <p style={{ color: 'var(--rn-red)' }}>{data.detailError}</p>
        <button className="rn-btn rn-btn-secondary" onClick={() => data.loadPatientDetail(id)}>
          Try again
        </button>
      </div>
    )
  }

  return (
    <div style={{ padding: '32px 40px', maxWidth: 1160 }}>
      <button className="rn-btn rn-btn-ghost" style={{ paddingLeft: 0, fontSize: 13 }} onClick={() => navigate('/roster')}>
        ← All patients
      </button>

      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 20, flexWrap: 'wrap', marginTop: 4, marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 28, margin: 0 }}>{patientName}</h1>
          <p className="rn-muted" style={{ fontSize: 14, marginTop: 4 }}>
            {[
              profile?.age != null ? `${profile.age}` : null,
              profile?.mr_number,
              profile?.diagnosis,
              profile ? `Day ${profile.day_count}` : null,
            ]
              .filter(Boolean)
              .join(' · ')}
          </p>
        </div>
        {latestRisk && <RiskBadge level={latestRisk} />}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1.55fr 1fr', gap: 26, alignItems: 'start' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 22, minWidth: 0 }}>
          {weightPoints.length >= 2 && (
            <SectionCard title="Weight · kg">
              <TrendChart points={weightPoints} lineColor="var(--rn-red)" />
            </SectionCard>
          )}
          {sleepPoints.length >= 2 && (
            <SectionCard title="Sleep · hours">
              <TrendChart points={sleepPoints} lineColor="var(--rn-accent)" />
            </SectionCard>
          )}

          <SectionCard title="Check-in history">
            {timeline.length === 0 ? (
              <p className="rn-muted">No entries yet.</p>
            ) : (
              timeline.map((entry) => <EntryRow key={entry.id} entry={entry} />)
            )}
          </SectionCard>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 22, minWidth: 0 }}>
          <SectionCard title="Alert history">
            {alertHistory.length === 0 ? (
              <p className="rn-muted">No alerts.</p>
            ) : (
              alertHistory.map((a) => <AlertHistoryRow key={a.id} alert={a} />)
            )}
          </SectionCard>

          <SectionCard title="Doctor notes">
            <NotesPanel patientId={id} notes={notes} onAdd={data.addNote} />
          </SectionCard>
        </div>
      </div>
    </div>
  )
}

function SectionCard({ title, children }) {
  return (
    <div className="rn-card">
      <div className="rn-kicker" style={{ marginBottom: 12 }}>
        {title}
      </div>
      {children}
    </div>
  )
}

function EntryRow({ entry }) {
  const color = riskColor(entry.risk_result?.risk_level)
  const label =
    entry.entry_type === 'voice'
      ? entry.raw_transcript || 'Voice entry'
      : entry.symptom_names?.length
        ? entry.symptom_names.join(', ')
        : 'Quick check-in'
  const date = new Date(entry.timestamp)

  return (
    <div style={{ display: 'flex', gap: 14, padding: '10px 0', borderBottom: '1px solid var(--rn-divider)' }}>
      <div style={{ width: 60, flex: 'none', fontSize: 12, opacity: 0.6 }}>
        {date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
      </div>
      <div style={{ borderLeft: `2px solid ${color}`, paddingLeft: 12, flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14 }}>{label}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
          <RiskBadge level={entry.risk_result?.risk_level} />
          {entry.risk_result?.reasoning && (
            <span
              className="rn-muted"
              style={{ fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
            >
              {entry.risk_result.reasoning}
            </span>
          )}
        </div>
      </div>
    </div>
  )
}

function AlertHistoryRow({ alert }) {
  const color = riskColor(alert.risk_level)
  return (
    <div style={{ borderLeft: `2px solid ${color}`, paddingLeft: 12, marginBottom: 10 }}>
      <div style={{ fontSize: 14 }}>{alert.alert_text}</div>
      <div className="rn-muted" style={{ fontSize: 12 }}>
        {new Date(alert.created_at).toLocaleString(undefined, {
          month: 'short',
          day: 'numeric',
          hour: 'numeric',
          minute: '2-digit',
        })}
        {alert.reviewed ? ' · reviewed' : ' · unreviewed'}
      </div>
    </div>
  )
}

function NotesPanel({ patientId, notes, onAdd }) {
  const [draft, setDraft] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)

  async function handleSave() {
    const text = draft.trim()
    if (!text) return
    setSaving(true)
    setError(null)
    try {
      await onAdd(patientId, text)
      setDraft('')
    } catch (e) {
      setError(e instanceof ApiException ? e.message : 'Could not save this note. Try again.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {notes.length === 0 ? (
        <p className="rn-muted" style={{ margin: 0 }}>
          No notes yet.
        </p>
      ) : (
        notes.map((n) => (
          <div key={n.id} style={{ paddingBottom: 10, borderBottom: '1px solid var(--rn-divider)' }}>
            <div style={{ fontSize: 14 }}>{n.note_text}</div>
            <div className="rn-muted" style={{ fontSize: 12 }}>
              {n.doctor_name} ·{' '}
              {new Date(n.created_at).toLocaleString(undefined, {
                month: 'short',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
              })}
            </div>
          </div>
        ))
      )}
      <textarea
        className="rn-input"
        style={{ minHeight: 76 }}
        placeholder="Discussed weight trend, advised daily weigh-ins…"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
      />
      {error && <span style={{ color: 'var(--rn-red)', fontSize: 13 }}>{error}</span>}
      <button className="rn-btn rn-btn-secondary" style={{ alignSelf: 'flex-start' }} onClick={handleSave} disabled={saving || !draft.trim()}>
        {saving ? 'Saving…' : 'Save note'}
      </button>
    </div>
  )
}
