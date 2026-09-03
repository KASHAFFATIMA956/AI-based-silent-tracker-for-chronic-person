import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAdminData } from '../../state/AdminDataContext'

const ROLE_LABELS = { patient: 'Patient', doctor: 'Doctor', attendant: 'Attendant', admin: 'Admin' }

// GET /admin/users — the admin home / "People & roles" screen, the only
// admin screen this build has (smallest remaining role scope — same
// instruction the Flutter admin build followed, see
// context/conventions.md). Content/layout source: the prototype's
// a-people screen (RozNoor.dc.html) — a searchable table, same table
// pattern PatientRosterScreen already uses for the doctor role. The
// prototype's "Red-flag rule sets" card (no backing endpoint/data) is left
// out, same as mobile_app's admin build — see context/decisions-log.md.
// No "Account" status column either: `users` has no status column and
// none was added — see context/api-contracts.md.
export function PeopleScreen() {
  const data = useAdminData()
  const navigate = useNavigate()
  const [query, setQuery] = useState('')

  const q = query.trim().toLowerCase()
  const filtered = q
    ? data.users.filter(
        (u) => u.name.toLowerCase().includes(q) || u.phone_or_email.toLowerCase().includes(q),
      )
    : data.users

  return (
    <div style={{ padding: '32px 40px', maxWidth: 1080 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 16, flexWrap: 'wrap', marginBottom: 22 }}>
        <h1 style={{ fontSize: 28 }}>People &amp; roles</h1>
        <span className="rn-muted" style={{ fontSize: 13 }}>
          Accounts, disease tracks and clinician-reviewed rule sets
        </span>
        <button
          className="rn-btn rn-btn-primary"
          style={{ marginLeft: 'auto' }}
          onClick={() => navigate('/people/new')}
        >
          Invite a person
        </button>
      </div>

      <input
        className="rn-input"
        style={{ maxWidth: 340, marginBottom: 20 }}
        placeholder="Search name or phone/email"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />

      {data.isLoading && data.users.length === 0 && <p>Loading…</p>}
      {data.loadError && data.users.length === 0 && (
        <p style={{ color: 'var(--rn-red)' }}>{data.loadError}</p>
      )}
      {!data.isLoading && !data.loadError && filtered.length === 0 && (
        <p className="rn-muted">
          {data.users.length === 0 ? 'No accounts yet.' : 'No one matches this search.'}
        </p>
      )}

      {filtered.length > 0 && (
        <div style={{ overflowX: 'auto' }}>
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: '1.5fr 1fr 1.4fr 1.2fr',
              fontSize: 11,
              letterSpacing: '0.08em',
              textTransform: 'uppercase',
              opacity: 0.6,
              borderBottom: '1px solid var(--rn-divider)',
              padding: '0 8px 9px',
              minWidth: 760,
            }}
          >
            <span>Person</span>
            <span>Role</span>
            <span>Linked to</span>
            <span>Disease track</span>
          </div>
          {filtered.map((u) => (
            <PersonRow key={u.id} user={u} onOpen={() => navigate(`/people/${u.id}/edit`)} />
          ))}
        </div>
      )}
    </div>
  )
}

function PersonRow({ user, onOpen }) {
  return (
    <div
      onClick={onOpen}
      style={{
        display: 'grid',
        gridTemplateColumns: '1.5fr 1fr 1.4fr 1.2fr',
        alignItems: 'center',
        padding: '14px 8px',
        borderBottom: '1px solid var(--rn-divider)',
        cursor: 'pointer',
        fontSize: 14,
        minWidth: 760,
      }}
    >
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
        <b style={{ fontFamily: 'Space Grotesk, sans-serif', fontSize: 17, fontWeight: 600 }}>{user.name}</b>
        <span className="rn-muted" style={{ fontSize: 12 }}>
          {user.phone_or_email}
        </span>
      </span>
      <span>
        <span className="rn-tag" style={{ fontSize: 12 }}>
          {ROLE_LABELS[user.role] ?? user.role}
        </span>
      </span>
      <span style={{ opacity: 0.8 }}>{user.linked_summary ?? '—'}</span>
      <span style={{ opacity: 0.8 }}>{user.diagnosis ?? '—'}</span>
    </div>
  )
}
