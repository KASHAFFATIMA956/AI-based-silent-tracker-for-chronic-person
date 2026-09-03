import { useNavigate } from 'react-router-dom'
import { BilingualText } from '../../components/BilingualText'
import { RiskDot } from '../../components/RiskBadge'
import { useAuth } from '../../state/AuthContext'
import { usePatientData } from '../../state/PatientDataContext'

// Home — content/layout source is the prototype's p-home screen
// (UI Inspo/.../RozNoor.dc.html: the big "Tap and speak" card + a status
// card side by side, then a grid of nav cards, then Emergency + the
// disclaimer line) — same content mobile_app's home_screen.dart already
// adapted to a phone layout; this uses the prototype's actual desktop
// two-column layout directly since a web app has the room for it.
export function HomeScreen() {
  const data = usePatientData()
  const { session } = useAuth()
  const navigate = useNavigate()

  if (data.isLoading && !data.profile) {
    return <CenteredMessage>Loading…</CenteredMessage>
  }
  if (data.loadError && !data.profile) {
    return (
      <CenteredMessage>
        <p>{data.loadError}</p>
        <button className="rn-btn rn-btn-secondary" onClick={() => session?.patientId && data.loadAll(session.patientId)}>
          Try again
        </button>
      </CenteredMessage>
    )
  }

  const latest = data.latestEntry
  const risk = latest?.risk_result

  return (
    <div style={{ padding: '32px 40px', maxWidth: 1080 }}>
      <BilingualText as="h1" en="How are you feeling today?" ur="Aaj aap kaise hain?" style={{ fontSize: 32 }} />
      <p className="rn-muted" style={{ marginTop: 8, marginBottom: 26 }}>
        {data.profile ? `Day ${data.profile.day_count} · baseline learned from ${data.timeline.length} entries` : ''}
      </p>

      <div style={{ display: 'flex', gap: 22, flexWrap: 'wrap', alignItems: 'stretch' }}>
        <button
          className="rn-card"
          onClick={() => navigate('/voice')}
          style={{ flex: '1 1 340px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16, padding: '36px 26px', borderColor: 'var(--rn-accent)' }}
        >
          <span style={{ width: 96, height: 96, borderRadius: '50%', border: '1.5px solid var(--rn-accent)', display: 'grid', placeItems: 'center', color: 'var(--rn-accent)' }}>
            <MicIcon size={38} />
          </span>
          <BilingualText as="span" en="Tap and speak" ur="Bol kar batayein" style={{ fontSize: 20, fontFamily: 'Space Grotesk, sans-serif', fontWeight: 600 }} />
          <span className="rn-muted" style={{ fontSize: 14 }}>10 seconds is enough</span>
        </button>

        <div className="rn-card" style={{ flex: '1 1 320px', padding: 26, display: 'flex', flexDirection: 'column', gap: 10, justifyContent: 'center' }}>
          <span className="rn-kicker">TODAY'S STATUS</span>
          {!latest ? (
            <p style={{ margin: 0 }}>No entries yet — your first check-in starts your baseline.</p>
          ) : (
            <>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <RiskDot level={risk?.risk_level} />
                <span style={{ fontFamily: 'Space Grotesk, sans-serif', fontSize: 22 }}>{risk?.risk_title ?? 'Recorded'}</span>
              </div>
              <p className="rn-muted" style={{ margin: 0 }}>{risk?.risk_message ?? ''}</p>
            </>
          )}
        </div>
      </div>

      <hr className="rn-hr" style={{ margin: '30px 0' }} />

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(230px, 1fr))', gap: 18 }}>
        <NavCard kicker="30 seconds" title="Daily Check-in" subtitle="Sleep, energy, mood, appetite, mobility, medicine" onClick={() => navigate('/check-in')} />
        <NavCard kicker="History" title="My Timeline" subtitle="Every entry, day by day, in your own words" onClick={() => navigate('/timeline')} />
        <NavCard kicker="This week" title="Silent Trend digest" subtitle="Quiet changes we noticed across seven days" onClick={() => navigate('/digest')} />
      </div>

      <p style={{ marginTop: 30, fontSize: 12, fontStyle: 'italic', opacity: 0.55, maxWidth: '70ch' }}>
        RozNoor supports you and your care team. It does not diagnose. In an emergency, contact your doctor or emergency services immediately.
      </p>
    </div>
  )
}

function NavCard({ kicker, title, subtitle, onClick }) {
  return (
    <button className="rn-card" onClick={onClick} style={{ display: 'flex', flexDirection: 'column', gap: 4, padding: 20 }}>
      <span className="rn-kicker">{kicker.toUpperCase()}</span>
      <span style={{ fontSize: 18, fontWeight: 600, fontFamily: 'Space Grotesk, sans-serif' }}>{title}</span>
      <span className="rn-muted" style={{ fontSize: 13 }}>{subtitle}</span>
    </button>
  )
}

function MicIcon({ size = 24 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 19v3" />
      <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
      <rect x="9" y="2" width="6" height="13" rx="3" />
    </svg>
  )
}

function CenteredMessage({ children }) {
  return (
    <div style={{ display: 'grid', placeItems: 'center', minHeight: '60vh', padding: 24, textAlign: 'center' }}>
      <div>{children}</div>
    </div>
  )
}
