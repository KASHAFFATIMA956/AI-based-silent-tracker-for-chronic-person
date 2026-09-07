import { createContext, useCallback, useContext, useEffect, useState } from 'react'

// Paper (light) / Nocturne (dark) toggle — mirrors
// mobile_app/lib/state/theme_provider.dart. A pure client display
// preference with no server-side "account truth" to defer to (unlike
// language_preference), so persisting it locally is unambiguously correct
// — localStorage here plays the same role shared_preferences does for the
// Flutter app (see context/decisions-log.md, 2026-08-27 entry — the same
// reasoning applies verbatim on web: this is a UI preference, not a
// secret, so it doesn't need the more careful handling given to the JWT in
// tokenStorage.js). Defaults to Paper (light) on first load, matching the
// prototype's own default.
const THEME_KEY = 'roznoor_theme_mode'
const ThemeContext = createContext(null)

export function ThemeProvider({ children }) {
  const [isDark, setIsDarkState] = useState(() => {
    try {
      return localStorage.getItem(THEME_KEY) === 'dark'
    } catch {
      return false
    }
  })

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light')
  }, [isDark])

  const setDark = useCallback((dark) => {
    setIsDarkState(dark)
    try {
      localStorage.setItem(THEME_KEY, dark ? 'dark' : 'light')
    } catch {
      // Best-effort persistence only — the in-session toggle above already
      // took effect regardless of whether the write succeeds.
    }
  }, [])

  const toggle = useCallback(() => setDark(!isDark), [isDark, setDark])

  return <ThemeContext.Provider value={{ isDark, setDark, toggle }}>{children}</ThemeContext.Provider>
}

export function useTheme() {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider')
  return ctx
}
