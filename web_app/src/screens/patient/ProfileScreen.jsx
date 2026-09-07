import { baselineStageLabel, medicationList } from '../../core/patientProfile'
import { useAuth } from '../../state/AuthContext'
import { useLanguage } from '../../state/LanguageContext'
import { usePatientData } from '../../state/PatientDataContext'
import { useTheme } from '../../state/ThemeContext'

// Profile — real patient data (GET /patients/{id} + GET /auth/me),
// view-only: there is no PATCH /patients/{id} or PATCH /auth/me endpoint,
// so no field here is editable — mirrors
// mobile_app/lib/screens/patient/profile_screen.dart exactly, same gap
// flagged there.
export function ProfileScreen() {
  const { session } = useAuth()
  const { profile } = usePatientData()
  const { isRomanUrdu, setRomanUrdu } = useLanguage()
  const { isDark, setDark } = useTheme()

  if (!profile) return <p style={{ padding: 32 }}>Loading…</p>

  const meds = medicationList(profile)

  return (
    <div style={{ padding: '32px 40px', maxWidth: 820 }}>
      <h1 style={{ fontSize: 28 }}>My Profile</h1>
      <p className="rn-muted" style={{ marginTop: 6, marginBottom: 22 }}>
        Set once with your attendant. Everything here shapes which safety rules apply to you.
      </p>

      <SectionCard
        title="Person"
        rows={[
          ['Full name', session?.name ?? '—'],
          ['Age', profile.age?.toString() ?? '—'],
          ['Attendant', profile.attendant_name ?? '—'],
          ['Language preference', session?.languagePreference === 'roman_urdu' ? 'Roman Urdu' : 'English'],
        ]}
      />

      <div style={{ height: 16 }} />

      <SectionCard
        title="Condition"
        rows={[
          ['Diagnosis', profile.diagnosis ?? '—'],
          ['MR number', profile.mr_number ?? '—'],
          ['Treating doctor', profile.assigned_doctor_name ?? '—'],
          ['Emergency contact', `${profile.emergency_contact_name ?? '—'} · ${profile.emergency_contact_phone ?? ''}`],
        ]}
      >
        {meds.length > 0 && (
          <>
            <hr className="rn-hr" style={{ margin: '18px 0' }} />
            <span className="rn-kicker">MEDICINES</span>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 10 }}>
              {meds.map((m) => (
                <span key={m} className="rn-chip">{m}</span>
              ))}
            </div>
          </>
        )}
      </SectionCard>

      <div className="rn-card" style={{ marginTop: 16, padding: 24, borderColor: 'var(--rn-accent-300)' }}>
        <span className="rn-kicker">BASELINE STATUS</span>
        <div style={{ fontSize: 19, fontWeight: 600, margin: '10px 0 12px' }}>{baselineStageLabel(profile)}</div>
        <div style={{ height: 6, borderRadius: 3, background: 'var(--rn-accent-100)', overflow: 'hidden' }}>
          <div style={{ height: '100%', width: `${Math.min(100, (profile.day_count / 15) * 100)}%`, background: 'var(--rn-accent-400)' }} />
        </div>
        <p className="rn-muted" style={{ fontSize: 14, marginTop: 10 }}>
          Day {profile.day_count} of monitoring. Days 1-7 collect your first ranges, days 8-14 learn them. From day 15
          your deviations are measured against your own history.
        </p>
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 22 }}>
        <span>Roman Urdu</span>
        <ToggleSwitch checked={isRomanUrdu} onChange={setRomanUrdu} />
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 16 }}>
        <span>Appearance</span>
        <div style={{ display: 'flex', border: '1px solid var(--rn-divider)', borderRadius: 10, overflow: 'hidden' }}>
          {[
            ['Paper', false],
            ['Nocturne', true],
          ].map(([label, dark]) => (
            <button
              key={label}
              onClick={() => setDark(dark)}
              className="rn-btn"
              style={{
                borderRadius: 0,
                padding: '9px 18px',
                fontSize: 14,
                border: 'none',
                background: isDark === dark ? 'var(--rn-accent-200)' : 'transparent',
                color: isDark === dark ? 'var(--rn-accent-dark)' : 'var(--rn-text)',
              }}
            >
              {label}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

function SectionCard({ title, rows, children }) {
  return (
    <div className="rn-card" style={{ padding: 24 }}>
      <span className="rn-kicker">{title.toUpperCase()}</span>
      <div style={{ marginTop: 14, display: 'flex', flexDirection: 'column', gap: 12 }}>
        {rows.map(([label, value]) => (
          <div key={label}>
            <div className="rn-muted" style={{ fontSize: 12 }}>{label}</div>
            <div style={{ fontSize: 16 }}>{value}</div>
          </div>
        ))}
      </div>
      {children}
    </div>
  )
}

function ToggleSwitch({ checked, onChange }) {
  return (
    <button
      onClick={() => onChange(!checked)}
      style={{
        width: 44,
        height: 26,
        borderRadius: 999,
        border: 'none',
        background: checked ? 'var(--rn-accent)' : 'var(--rn-divider)',
        position: 'relative',
        cursor: 'pointer',
        transition: 'background 0.15s ease',
      }}
      aria-pressed={checked}
    >
      <span
        style={{
          position: 'absolute',
          top: 3,
          left: checked ? 21 : 3,
          width: 20,
          height: 20,
          borderRadius: '50%',
          background: '#fff',
          transition: 'left 0.15s ease',
        }}
      />
    </button>
  )
}
