import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useAuth } from '../state/AuthContext'

// Persistent nav shell for the admin role — a single "People & roles"
// section, matching the prototype's own single a-people screen (no other
// admin screens exist this session — see context/conventions.md,
// "smallest remaining scope"). Same sidebar shape as DoctorShell/
// PatientShell for visual consistency across roles, even though there's
// only one real destination here.
export function AdminShell() {
  const { session, logout } = useAuth()
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
        <ShellNavItem to="/people" label="People & roles" />

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

function ShellNavItem({ to, label }) {
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
    </NavLink>
  )
}
