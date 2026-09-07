import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { ApiException } from '../../core/apiClient'
import { useAdminData } from '../../state/AdminDataContext'

const ROLES = ['patient', 'doctor', 'attendant', 'admin']
const LANGUAGES = ['english', 'roman_urdu']
const roleLabel = (r) => r[0].toUpperCase() + r.slice(1)
const languageLabel = (l) => (l === 'roman_urdu' ? 'Roman Urdu' : 'English')

// One form for both creating a new user (any role, POST /admin/users) and
// editing an existing one (PATCH /admin/users/{id}) — mirrors
// mobile_app/lib/screens/admin/user_form_screen.dart (one shared screen,
// not two), same "smallest remaining scope" instruction. Route param
// `userId` present => edit mode; absent (`/people/new`) => create mode.
//
// Edit mode looks the existing user up from AdminDataContext's
// already-loaded `users` list instead of a dedicated GET
// /admin/users/{id} endpoint, which doesn't exist — same "look it up from
// already-loaded data" pattern PatientDetailScreen.jsx uses for the
// missing-patient-name gap (see context/decisions-log.md). This also means
// a direct URL/refresh at /people/:userId/edit correctly waits for the
// list to load (same App.jsx effect that loads it on every admin sign-in,
// mirroring the doctor role's roster/alerts) rather than crashing, and
// falls back to a plain "not found" message if the id genuinely doesn't
// exist rather than rendering a blank form.
export function UserFormScreen() {
  const { userId } = useParams()
  const isEdit = userId !== undefined
  const data = useAdminData()
  const navigate = useNavigate()

  const existing = useMemo(
    () => (isEdit ? data.users.find((u) => String(u.id) === userId) : null),
    [isEdit, userId, data.users],
  )

  const [name, setName] = useState(existing?.name ?? '')
  const [role, setRole] = useState(existing?.role ?? 'patient')
  const [identifier, setIdentifier] = useState(existing?.phone_or_email ?? '')
  const [language, setLanguage] = useState(existing?.language_preference ?? 'english')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [errorText, setErrorText] = useState(null)

  // Only a genuine "not found" once the list has actually loaded — while
  // data.users is still empty (first paint, or a direct-URL page load
  // still awaiting App.jsx's load effect) this correctly falls through to
  // the form below instead of flashing a false "not found".
  if (isEdit && data.users.length > 0 && !existing) {
    return (
      <div style={{ padding: '32px 40px', maxWidth: 640 }}>
        <p className="rn-muted">This account couldn't be found — it may have been renamed. Go back and try again.</p>
        <button className="rn-btn rn-btn-secondary" onClick={() => navigate('/people')}>
          Back to People
        </button>
      </div>
    )
  }

  async function handleSubmit(e) {
    e.preventDefault()
    if (!name.trim()) return setErrorText('Enter a name')
    if (!identifier.trim()) return setErrorText('Enter a phone or email')
    if (!isEdit && !password) return setErrorText('Set a password for this account')
    setErrorText(null)
    setSubmitting(true)
    try {
      if (isEdit) {
        await data.updateUser(existing.id, {
          name: name.trim(),
          role,
          phoneOrEmail: identifier.trim(),
          languagePreference: language,
        })
      } else {
        await data.createUser({
          name: name.trim(),
          role,
          phoneOrEmail: identifier.trim(),
          password,
          languagePreference: language,
        })
      }
      navigate('/people')
    } catch (err) {
      setErrorText(err instanceof ApiException ? err.message : 'Something went wrong. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div style={{ padding: '32px 40px', maxWidth: 640 }}>
      <h1 style={{ fontSize: 26, marginBottom: 20 }}>{isEdit ? 'Edit person' : 'Invite a person'}</h1>
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16, maxWidth: 420 }}>
        {errorText && (
          <p style={{ color: 'var(--rn-red)', fontSize: 13, margin: 0 }}>{errorText}</p>
        )}

        <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <span style={{ fontSize: 13 }}>Full name</span>
          <input className="rn-input" value={name} onChange={(e) => setName(e.target.value)} />
        </label>

        <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <span style={{ fontSize: 13 }}>Role</span>
          <select className="rn-input" value={role} onChange={(e) => setRole(e.target.value)}>
            {ROLES.map((r) => (
              <option key={r} value={r}>
                {roleLabel(r)}
              </option>
            ))}
          </select>
        </label>

        <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <span style={{ fontSize: 13 }}>Phone or email</span>
          <input
            className="rn-input"
            type="text"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            autoComplete="username"
          />
        </label>

        {!isEdit ? (
          <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span style={{ fontSize: 13 }}>Password</span>
            <div style={{ position: 'relative' }}>
              <input
                className="rn-input"
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="new-password"
                style={{ paddingRight: 44 }}
              />
              <button
                type="button"
                className="rn-btn rn-btn-ghost"
                style={{ position: 'absolute', right: 2, top: 2, padding: '8px 10px', fontSize: 12 }}
                onClick={() => setShowPassword((v) => !v)}
              >
                {showPassword ? 'Hide' : 'Show'}
              </button>
            </div>
          </label>
        ) : (
          // No password field in edit mode — PATCH /admin/users/{id}
          // doesn't support changing it (see context/api-contracts.md);
          // flag that plainly rather than silently omitting it, same as
          // the Flutter form's own inline note.
          <p className="rn-muted" style={{ fontSize: 12, margin: 0 }}>
            Password can&apos;t be changed here — this account keeps its existing password.
          </p>
        )}

        <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <span style={{ fontSize: 13 }}>Language preference</span>
          <select className="rn-input" value={language} onChange={(e) => setLanguage(e.target.value)}>
            {LANGUAGES.map((l) => (
              <option key={l} value={l}>
                {languageLabel(l)}
              </option>
            ))}
          </select>
        </label>

        <div style={{ display: 'flex', gap: 10, marginTop: 8 }}>
          <button type="submit" className="rn-btn rn-btn-primary" disabled={submitting}>
            {submitting ? 'Saving…' : isEdit ? 'Save changes' : 'Create user'}
          </button>
          <button type="button" className="rn-btn rn-btn-secondary" onClick={() => navigate('/people')}>
            Cancel
          </button>
        </div>
      </form>
    </div>
  )
}
