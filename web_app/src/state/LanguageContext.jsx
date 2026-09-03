import { createContext, useCallback, useContext, useState } from 'react'

// English / Roman Urdu toggle — mirrors mobile_app/lib/state/language_provider.dart.
// Initialized from the account's language_preference (GET /auth/me) on
// login, then freely toggleable in-session. There is no PATCH endpoint to
// persist a change back to the account, so a toggle here only affects THIS
// session's UI text and the speech-recognition locale, not the stored
// preference — same flagged limitation as the Flutter app, see
// context/decisions-log.md.
const LanguageContext = createContext(null)

export function LanguageProvider({ children }) {
  const [isRomanUrdu, setIsRomanUrdu] = useState(false)

  const setFromAccountPreference = useCallback((preference) => {
    setIsRomanUrdu(preference === 'roman_urdu')
  }, [])

  const toggle = useCallback(() => setIsRomanUrdu((v) => !v), [])
  const setRomanUrdu = useCallback((value) => setIsRomanUrdu(value), [])

  // Locale id passed to the Web Speech API — see
  // src/screens/patient/VoiceDiaryScreen.jsx and context/decisions-log.md
  // for why this is the mechanism through which the toggle "affects what's
  // sent to voice entry processing," not just static text — same intent as
  // LanguageProvider.speechLocaleId in the Flutter app.
  const speechLocaleId = isRomanUrdu ? 'ur-PK' : 'en-US'

  return (
    <LanguageContext.Provider value={{ isRomanUrdu, setFromAccountPreference, toggle, setRomanUrdu, speechLocaleId }}>
      {children}
    </LanguageContext.Provider>
  )
}

export function useLanguage() {
  const ctx = useContext(LanguageContext)
  if (!ctx) throw new Error('useLanguage must be used within LanguageProvider')
  return ctx
}
