import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { RiskBadge } from '../../components/RiskBadge'
import { ApiException } from '../../core/apiClient'
import { riskColor } from '../../core/riskColors'
import { useDoctorData } from '../../state/DoctorDataContext'

// GET /doctors/{doctor_id}/alerts + POST /alerts/{alert_id}/review across
// the doctor's own patients. Content/layout source: the prototype's
// d-alerts screen — Unread/All filter + mark-reviewed action, matching
// mobile_app's live badge-count pattern (see context/conventions.md).
export function AlertsScreen() {
  const data = useDoctorData()
  const navigate = useNavigate()
  const [unreviewedOnly, setUnreviewedOnly] = useState(true)
  const [reviewingId, setReviewingId] = useState(null)
  const [reviewError, setReviewError] = useState(null)

  const alerts = unreviewedOnly ? data.alerts.filter((a) => !a.reviewed) : data.alerts

  async function handleReview(alertId) {
    setReviewingId(alertId)
    setReviewError(null)
    try {
      await data.reviewAlert(alertId)
    } catch (e) {
      setReviewError(e instanceof ApiException ? e.message : 'Could not mark this reviewed. Try again.')
    } finally {
      setReviewingId(null)
    }
  }

  return (
    <div style={{ padding: '32px 40px', maxWidth: 1080 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 16, flexWrap: 'wrap', marginBottom: 22 }}>
        <h1 style={{ fontSize: 28 }}>Alerts</h1>
        <span className="rn-muted" style={{ fontSize: 13 }}>
          {data.unreviewedAlertCount} unread
        </span>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
          <button
            className={unreviewedOnly ? 'rn-btn rn-btn-primary' : 'rn-btn rn-btn-secondary'}
            style={{ padding: '7px 16px', fontSize: 13 }}
            onClick={() => setUnreviewedOnly(true)}
          >
            Unread
          </button>
          <button
            className={!unreviewedOnly ? 'rn-btn rn-btn-primary' : 'rn-btn rn-btn-secondary'}
            style={{ padding: '7px 16px', fontSize: 13 }}
            onClick={() => setUnreviewedOnly(false)}
          >
            All
          </button>
        </div>
      </div>

      {reviewError && (
        <p style={{ color: 'var(--rn-red)', fontSize: 13 }}>{reviewError}</p>
      )}

      {data.isLoading && data.alerts.length === 0 && <p>Loading…</p>}
      {data.loadError && data.alerts.length === 0 && <p style={{ color: 'var(--rn-red)' }}>{data.loadError}</p>}
      {!data.isLoading && !data.loadError && alerts.length === 0 && (
        <p className="rn-muted">{unreviewedOnly ? 'No unreviewed alerts.' : 'No alerts yet.'}</p>
      )}

      {alerts.map((alert) => (
        <AlertRow
          key={alert.id}
          alert={alert}
          isReviewing={reviewingId === alert.id}
          onReview={() => handleReview(alert.id)}
          onOpenPatient={() => navigate(`/roster/${alert.patient_id}`)}
        />
      ))}
    </div>
  )
}

function AlertRow({ alert, isReviewing, onReview, onOpenPatient }) {
  const color = riskColor(alert.risk_level)
  return (
    <div
      className="rn-card"
      style={{
        display: 'grid',
        gridTemplateColumns: 'auto 1fr auto',
        gap: 18,
        alignItems: 'center',
        marginBottom: 10,
        borderLeft: `2px solid ${color}`,
        opacity: alert.reviewed ? 0.6 : 1,
      }}
    >
      <span className="rn-dot" style={{ background: color }} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, flexWrap: 'wrap' }}>
          <b style={{ fontFamily: 'Space Grotesk, sans-serif', fontSize: 17, fontWeight: 600 }}>{alert.patient_name}</b>
          <RiskBadge level={alert.risk_level} />
          <span className="rn-muted" style={{ fontSize: 12 }}>
            {new Date(alert.created_at).toLocaleString(undefined, {
              month: 'short',
              day: 'numeric',
              hour: 'numeric',
              minute: '2-digit',
            })}
          </span>
        </div>
        <span style={{ fontSize: 15, opacity: 0.85 }}>{alert.alert_text}</span>
        {alert.source_rule && (
          <span className="rn-muted" style={{ fontSize: 13, fontStyle: 'italic' }}>
            {alert.source_rule}
          </span>
        )}
      </div>
      <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
        {!alert.reviewed ? (
          <button className="rn-btn rn-btn-secondary" onClick={onReview} disabled={isReviewing}>
            {isReviewing ? 'Marking…' : 'Mark reviewed'}
          </button>
        ) : (
          <span className="rn-muted" style={{ fontSize: 13 }}>
            Reviewed
          </span>
        )}
        <button className="rn-btn rn-btn-primary" onClick={onOpenPatient}>
          Open patient
        </button>
      </div>
    </div>
  )
}
