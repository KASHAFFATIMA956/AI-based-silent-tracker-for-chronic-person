import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BilingualText } from '../../components/BilingualText'
import { useAuth } from '../../state/AuthContext'

// ONE login form, calling the same POST /auth/login either way — mirrors
// mobile_app/lib/screens/auth/login_screen.dart ("no duplicate auth
// logic", see context/decisions-log.md). `isClinician` only changes
// copy/accent color; it never changes which endpoint is called or how the
// response is handled. Post-login routing is decided entirely by App.jsx
// from the JWT's role, never by which entry point the user tapped.
export function LoginScreen() {
  const [isClinician, setIsClinician] = useState(false)
  const [identifier, setIdentifier] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [fieldError, setFieldError] = useState(null)
  const { login, lastError } = useAuth()
  const navigate = useNavigate()

  const accent = isClinician ? 'var(--rn-accent-2)' : 'var(--rn-accent)'

  async function handleSubmit(e) {
    e.preventDefault()
    if (!identifier.trim()) {
      setFieldError('Enter your phone or email')
      return
    }
    if (!password) {
      setFieldError('Enter your password')
      return
    }
    setFieldError(null)
    setSubmitting(true)
    const ok = await login(identifier.trim(), password)
    setSubmitting(false)
    if (ok) navigate('/home', { replace: true })
  }

  return (
    <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: '32px 28px' }}>
      <form onSubmit={handleSubmit} style={{ width: '100%', maxWidth: 420, display: 'flex', flexDirection: 'column', gap: 4 }}>
        <h1 style={{ textAlign: 'center', fontSize: 30, color: accent, letterSpacing: '0.3px' }}>RozNoor</h1>
        <p style={{ textAlign: 'center', fontSize: 11, letterSpacing: '1.2px', color: accent, opacity: 0.85, margin: '6px 0 40px' }}>
          Silent symptom &amp; personal baseline monitoring
        </p>

        {isClinician ? (
          <>
            <div style={{ textAlign: 'center', marginBottom: 18 }}>
              <span
                className="rn-tag"
                style={{ color: 'var(--rn-accent-2)', borderColor: 'transparent', background: 'color-mix(in srgb, var(--rn-accent-2) 12%, transparent)', fontSize: 11, letterSpacing: '1.4px' }}
              >
                CLINICIAN SIGN-IN
              </span>
            </div>
            <h2 style={{ textAlign: 'center', fontSize: 22 }}>Doctor &amp; admin sign in</h2>
            <p className="rn-muted" style={{ textAlign: 'center', marginTop: 6 }}>
              Use your clinic-issued credentials. You'll land on your dashboard automatically.
            </p>
          </>
        ) : (
          <>
            <BilingualText
              as="h2"
              en="How are you feeling today?"
              ur="Aaj aap kaise hain?"
              style={{ textAlign: 'center', fontSize: 24 }}
            />
            <p className="rn-muted" style={{ textAlign: 'center', marginTop: 10 }}>
              Sign in to log your daily check-in.
            </p>
          </>
        )}

        <div style={{ height: 24 }} />

        <label style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 16 }}>
          <span style={{ fontSize: 13 }}>Phone or email</span>
          <input
            className="rn-input"
            type="text"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            autoComplete="username"
          />
        </label>

        <label style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 8 }}>
          <span style={{ fontSize: 13 }}>Password</span>
          <div style={{ position: 'relative' }}>
            <input
              className="rn-input"
              type={showPassword ? 'text' : 'password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
              style={{ paddingRight: 44 }}
            />
            <button
              type="button"
              onClick={() => setShowPassword((v) => !v)}
              className="rn-btn rn-btn-ghost"
              style={{ position: 'absolute', right: 2, top: 2, padding: '8px 10px', fontSize: 12 }}
            >
              {showPassword ? 'Hide' : 'Show'}
            </button>
          </div>
        </label>

        {(fieldError || lastError) && (
          <p style={{ color: 'var(--rn-red)', fontSize: 13, margin: '4px 0 0' }}>{fieldError || lastError}</p>
        )}

        <button type="submit" className="rn-btn rn-btn-primary rn-btn-block" style={{ marginTop: 22, background: accent }} disabled={submitting}>
          {submitting ? 'Logging in…' : 'Log in'}
        </button>

        <div style={{ textAlign: 'center', marginTop: 22 }}>
          {isClinician ? (
            <button type="button" className="rn-btn rn-btn-ghost" style={{ fontSize: 13 }} onClick={() => setIsClinician(false)}>
              Back to patient sign in
            </button>
          ) : (
            <button type="button" className="rn-btn rn-btn-ghost" style={{ fontSize: 13 }} onClick={() => setIsClinician(true)}>
              Are you a doctor or admin? Log in here
            </button>
          )}
        </div>
      </form>
    </div>
  )
}
