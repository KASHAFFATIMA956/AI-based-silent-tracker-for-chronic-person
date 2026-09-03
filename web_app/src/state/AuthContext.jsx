import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import { ApiException } from '../core/apiClient'
import { tokenStorage } from '../core/tokenStorage'
import { authService } from '../services/authService'

// Mirrors mobile_app/lib/state/auth_provider.dart. `role` on the session is
// the ONLY signal any routing decision uses (see context/decisions-log.md —
// role-switcher tabs were removed for exactly this reason: routing must
// never be a user choice). Session persists via tokenStorage so the app
// stays signed in across restarts; restoreSession() runs once at startup
// before the router decides what to show — same shape as AuthProvider.

const AuthContext = createContext(null)

export const AUTH_STATUS = { UNKNOWN: 'unknown', SIGNED_OUT: 'signedOut', SIGNED_IN: 'signedIn' }

export function AuthProvider({ children }) {
  const [status, setStatus] = useState(AUTH_STATUS.UNKNOWN)
  const [session, setSession] = useState(null)
  const [lastError, setLastError] = useState(null)

  useEffect(() => {
    restoreSession()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function restoreSession() {
    const stored = tokenStorage.readSession()
    if (!stored) {
      setStatus(AUTH_STATUS.SIGNED_OUT)
      return
    }
    try {
      // Token exists locally — confirm it's still valid (not expired/
      // revoked) and pick up patient_id + language_preference via a real
      // /auth/me call rather than trusting the locally-cached role blindly.
      const resolved = await authService.fetchMe(stored)
      setSession(resolved)
      setStatus(AUTH_STATUS.SIGNED_IN)
    } catch {
      tokenStorage.clear()
      setStatus(AUTH_STATUS.SIGNED_OUT)
    }
  }

  const login = useCallback(async (phoneOrEmail, password) => {
    setLastError(null)
    try {
      let newSession = await authService.login(phoneOrEmail, password)
      tokenStorage.saveSession(newSession)
      // Resolve patient_id + language_preference immediately so every
      // downstream screen has them without a second round trip.
      newSession = await authService.fetchMe(newSession)
      setSession(newSession)
      setStatus(AUTH_STATUS.SIGNED_IN)
      return true
    } catch (e) {
      setLastError(e instanceof ApiException ? e.message : 'Something went wrong. Please try again.')
      setStatus(AUTH_STATUS.SIGNED_OUT)
      return false
    }
  }, [])

  const logout = useCallback(() => {
    tokenStorage.clear()
    setSession(null)
    setStatus(AUTH_STATUS.SIGNED_OUT)
  }, [])

  return (
    <AuthContext.Provider value={{ status, session, lastError, login, logout }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
