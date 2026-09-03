import { useState } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { EmergencyModal } from './EmergencyModal'
import { useAuth } from '../state/AuthContext'
import { useLanguage } from '../state/LanguageContext'
import { usePatientData } from '../state/PatientDataContext'
import { useTheme } from '../state/ThemeContext'

// Persistent nav shell for every patient screen — content/structure source
// is the prototype's desktop `aside.rn-side` "Patient" nav list
// (`UI Inspo/.../RozNoor.dc.html`), which mobile_app's PatientShell already
// adapted once (to a bottom tab bar, since it's a phone). A web app has
// room for the prototype's actual sidebar shape, so this uses that layout
// directly rather than mobile's tab-bar adaptation. Emergency button and
// the "silent symptom & personal baseline monitoring" strapline are pulled
// from the prototype's header verbatim.
export function PatientShell() {
  const { session, logout } = useAuth()
  const { profile } = usePatientData()
  const { isRomanUrdu, toggle: toggleLanguage } = useLanguage()
  const { isDark, toggle: toggleTheme } = useTheme()
  const navigate = useNavigate()
  const [showEmergency, setShowEmergency] = useState(false)

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
        <div style={{ padding: '0 14px 10px', fontSize: 11, letterSpacing: '0.1em', textTransform: 'uppercase', color: 'var(--rn-accent)' }}>
          {session?.name}
          {profile?.age ? ` · ${profile.age}` : ''}
        </div>
        <ShellNavItem to="/home" label="Home" />
        <ShellNavItem to="/voice" label="Voice Diary" />
        <ShellNavItem to="/check-in" label="Quick Check-in" />
        <ShellNavItem to="/timeline" label="My Timeline" />
        <ShellNavItem to="/digest" label="Weekly Trends" />
        <ShellNavItem to="/profile" label="My Profile" />

        <div style={{ marginTop: 'auto', padding: '18px 14px 0', display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div style={{ display: 'flex', gap: 8 }}>
            <button className="rn-btn rn-btn-secondary" style={{ flex: 1, padding: '8px 10px', fontSize: 13 }} onClick={toggleLanguage}>
              {isRomanUrdu ? 'اردو' : 'EN'}
            </button>
            <button className="rn-btn rn-btn-secondary" style={{ flex: 1, padding: '8px 10px', fontSize: 13 }} onClick={toggleTheme}>
              {isDark ? 'Nocturne' : 'Paper'}
            </button>
          </div>
          <button className="rn-btn rn-btn-danger" onClick={() => setShowEmergency(true)}>
            Emergency
          </button>
          <button className="rn-btn rn-btn-ghost" onClick={handleLogout}>
            Log out
          </button>
        </div>
      </aside>

      <main style={{ flex: 1, minWidth: 0 }}>
        <Outlet />
      </main>

      {showEmergency && <EmergencyModal profile={profile} onClose={() => setShowEmergency(false)} />}
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
      {label}
    </NavLink>
  )
}
