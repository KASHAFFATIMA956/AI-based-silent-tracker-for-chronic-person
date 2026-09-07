import { useAuth } from '../state/AuthContext'

// Landing screen for doctor/admin roles until the web dashboard for those
// roles is built (explicitly next-session scope — see
// context/conventions.md, which points at the prototype's
// d-patients/d-detail/d-alerts/a-people screens as that work's content
// source, same as it did for the Flutter doctor build). Routed to purely
// from JWT role, never a user selection — mirrors
// mobile_app/lib/screens/placeholder_screen.dart.
export function PlaceholderScreen() {
  const { session, logout } = useAuth()
  const role = session?.role ?? ''
  const roleLabel = role ? role[0].toUpperCase() + role.slice(1) : ''

  return (
    <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 28 }}>
      <div style={{ maxWidth: 420, textAlign: 'center' }}>
        <h2 style={{ fontSize: 22, marginBottom: 10 }}>Welcome, {session?.name}</h2>
        <p className="rn-muted">The {roleLabel} dashboard is built in a later phase of this app.</p>
        <button className="rn-btn rn-btn-secondary" style={{ marginTop: 24 }} onClick={logout}>
          Log out
        </button>
      </div>
    </div>
  )
}
