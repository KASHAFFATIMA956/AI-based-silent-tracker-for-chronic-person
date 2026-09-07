import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useAuth } from '../state/AuthContext'
import { useDoctorData } from '../state/DoctorDataContext'

// Persistent nav shell for the doctor role — Patients / Alerts, matching
// the prototype's own two independently-reachable sidebar items
// (d-patients/d-alerts); d-detail is reached only by opening a patient
// (click), not a nav item of its own — same structure
// mobile_app/lib/widgets/doctor_shell.dart uses (there, a bottom-tab bar,
// since it's a phone; here, the prototype's actual sidebar shape, same
// adaptation PatientShell already made for the patient role on web). No
// language/theme toggles here — the Flutter doctor shell doesn't carry
// them either (they live on the patient Profile screen, which the doctor
// role has no equivalent of), so this isn't re-adding scope the sibling
// build didn't have.
export function DoctorShell() {
  const { session, logout } = useAuth()
  const { unreviewedAlertCount } = useDoctorData()
  const navigate = useNavigate()

  function handleLogout() {
    logout()
    navigate('/login', { replace: true })
  }

  return (
    <div style={{ display: 'flex', minHeight: '100vh' }}>
      <aside
        style={{
          flex: '0 0 246px',
          borderRight: '1px solid var(--rn-divider)',
          padding: '22px 0',
          display: 'flex',
          flexDirection: 'column',
          gap: 2,
        }}
      >
        <div style={{ padding: '0 14px 16px', fontSize: 24, fontFamily: 'Space Grotesk, sans-serif' }}>
          RozNoor
        </div>
        <div
          style={{
            padding: '0 14px 10px',
            fontSize: 11,
            letterSpacing: '0.1em',
            textTransform: 'uppercase',
            color: 'var(--rn-accent)',
          }}
        >
          {session?.name}
        </div>
        <ShellNavItem to="/roster" label="Patients" />
        <ShellNavItem to="/notifications" label="Alerts" badge={unreviewedAlertCount} />

        <div style={{ marginTop: 'auto', padding: '18px 14px 0' }}>
          <button className="rn-btn rn-btn-ghost" onClick={handleLogout}>
            Log out
          </button>
        </div>
      </aside>

      <main style={{ flex: 1, minWidth: 0 }}>
        <Outlet />
      </main>
    </div>
  )
}

function ShellNavItem({ to, label, badge }) {
  return (
    <NavLink
      to={to}
      style={({ isActive }) => ({
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        padding: '11px 14px',
        fontSize: 15,
        textDecoration: 'none',
        color: isActive ? 'var(--rn-accent-dark)' : 'var(--rn-text)',
        borderLeft: `2px solid ${isActive ? 'var(--rn-accent)' : 'transparent'}`,
        background: isActive ? 'var(--rn-accent-200)' : 'transparent',
      })}
    >
      <span>{label}</span>
      {badge > 0 && (
        <span
          style={{
            marginLeft: 'auto',
            background: 'var(--rn-red)',
            color: 'white',
            fontSize: 11,
            fontWeight: 700,
            borderRadius: 999,
            padding: '1px 7px',
          }}
        >
          {badge}
        </span>
      )}
    </NavLink>
  )
}
