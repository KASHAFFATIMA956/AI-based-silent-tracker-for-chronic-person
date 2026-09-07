import { useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { ChestPainFirstAidPanel } from '../../components/ChestPainFirstAidPanel'
import { EmergencyModal } from '../../components/EmergencyModal'
import { RiskDot } from '../../components/RiskBadge'
import { riskColor } from '../../core/riskColors'
import { usePatientData } from '../../state/PatientDataContext'

// Displays the risk_result returned from a POST /entries submission
// (risk_level, risk_title, risk_message, reasoning) — mirrors
// mobile_app/lib/screens/patient/result_screen.dart. The just-submitted
// entry is passed via router state (React Router's equivalent of Flutter
// passing the Entry object directly through Navigator) rather than
// re-fetched, same "already have the data, don't ask again" intent.
export function ResultScreen() {
  const location = useLocation()
  const navigate = useNavigate()
  const { profile } = usePatientData()
  const [showEmergency, setShowEmergency] = useState(false)
  const entry = location.state?.entry

  useEffect(() => {
    // Reached directly (refresh, bookmark) with no entry in router state —
    // no corresponding real-world action, redirect somewhere useful
    // instead of rendering a blank result. Done in an effect, not during
    // render, since navigating another component's route from mid-render
    // is undefined behavior in React.
    if (!entry) navigate('/timeline', { replace: true })
  }, [entry, navigate])

  if (!entry) return null

  const risk = entry.risk_result
  const color = riskColor(risk?.risk_level)
  // Wired at the display layer only, per the task's explicit instruction —
  // app/services/rules.py's scoring is unchanged. "Chest pain" is the
  // exact literal HEART_FAILURE_RULES["hard_red_symptoms"] checks
  // against, so this isolates the chest-pain hard flag from a Red caused
  // purely by the weight-gain hard flag.
  const showChestPainFirstAid = risk?.risk_level === 'Red' && entry.symptom_names?.includes('Chest pain')

  return (
    <div style={{ padding: '32px 40px', maxWidth: 900 }}>
      <span className="rn-kicker" style={{ display: 'block', marginBottom: 10 }}>
        Entry analysed · {new Date(entry.timestamp).toLocaleString(undefined, { hour: 'numeric', minute: '2-digit' })}
      </span>

      <div className="rn-card" style={{ padding: 30, borderColor: color, borderLeftWidth: 3 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
          <RiskDot level={risk?.risk_level} size={13} />
          <span style={{ fontFamily: 'Space Grotesk, sans-serif', fontSize: 32, color }}>{risk?.risk_title ?? 'Recorded'}</span>
          <span className="rn-tag" style={{ color, borderColor: color, marginLeft: 'auto' }}>{risk?.risk_level}</span>
        </div>
        <p style={{ fontSize: 18, marginTop: 14 }}>{risk?.risk_message ?? ''}</p>
        {risk?.reasoning && <p className="rn-muted" style={{ fontSize: 15 }}>{risk.reasoning}</p>}
      </div>

      {showChestPainFirstAid && <ChestPainFirstAidPanel />}

      {entry.symptom_names?.length > 0 && (
        <div className="rn-card" style={{ marginTop: 16, padding: 20, display: 'flex', flexDirection: 'column', gap: 10 }}>
          <span className="rn-kicker">WHAT WE HEARD</span>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {entry.symptom_names.map((s) => (
              <span key={s} className="rn-tag" style={{ color: 'var(--rn-accent-dark)', borderColor: 'transparent', background: 'var(--rn-accent-200)' }}>
                {s}
              </span>
            ))}
          </div>
          <p style={{ fontSize: 12, fontStyle: 'italic', opacity: 0.55, margin: 0 }}>
            Everyday words matched to tracked signals. Nothing was inferred beyond what you said.
          </p>
        </div>
      )}

      <div style={{ display: 'flex', gap: 12, marginTop: 22, flexWrap: 'wrap' }}>
        <button className="rn-btn rn-btn-danger" onClick={() => setShowEmergency(true)}>
          Contact my doctor
        </button>
        <button className="rn-btn rn-btn-primary" onClick={() => navigate('/timeline')}>
          See my timeline
        </button>
      </div>

      {showEmergency && <EmergencyModal profile={profile} onClose={() => setShowEmergency(false)} />}
    </div>
  )
}
