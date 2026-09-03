// JWT persistence for the web app.
//
// Mirrors mobile_app/lib/core/secure_storage.dart's role but NOT its
// mechanism — see context/decisions-log.md ("JWT storage on web") for the
// full reasoning. Short version: `flutter_secure_storage` maps to OS
// Keychain/Keystore, which has no browser equivalent. The safest browser
// option, an httpOnly cookie set BY THE SERVER, isn't available either
// without a backend change (POST /auth/login returns the token in a JSON
// body only — see context/api-contracts.md — it never sets a Set-Cookie
// header, and this session's task is explicitly backend-frozen). Between
// the remaining client-side options (in-memory only, sessionStorage,
// localStorage), this uses localStorage so a signed-in patient stays
// signed in across a closed tab/browser restart — matching the Flutter
// app's actual persisted-session behavior, which this session's task asked
// the web app to mirror. The real trade-off, flagged plainly: localStorage
// is readable by any JS that runs on this origin, so a successful XSS
// against this app can steal the token for its full 24h life (same expiry
// as mobile — see context/conventions.md). Mitigated only by React's
// default output-escaping (no `dangerouslySetInnerHTML` anywhere in this
// app) and the token's existing 24h expiry/no-refresh-token design
// (context/conventions.md) — not eliminated. A production deployment
// should move this to a real httpOnly cookie once the backend can set one.
const TOKEN_KEY = 'roznoor_access_token'
const USER_ID_KEY = 'roznoor_user_id'
const ROLE_KEY = 'roznoor_role'
const NAME_KEY = 'roznoor_name'

export const tokenStorage = {
  saveSession({ token, userId, role, name }) {
    localStorage.setItem(TOKEN_KEY, token)
    localStorage.setItem(USER_ID_KEY, String(userId))
    localStorage.setItem(ROLE_KEY, role)
    localStorage.setItem(NAME_KEY, name)
  },

  readToken() {
    return localStorage.getItem(TOKEN_KEY)
  },

  readSession() {
    const token = localStorage.getItem(TOKEN_KEY)
    if (!token) return null
    const userId = localStorage.getItem(USER_ID_KEY)
    const role = localStorage.getItem(ROLE_KEY)
    const name = localStorage.getItem(NAME_KEY)
    if (!userId || !role || !name) return null
    return { token, userId: Number(userId), role, name }
  },

  clear() {
    localStorage.removeItem(TOKEN_KEY)
    localStorage.removeItem(USER_ID_KEY)
    localStorage.removeItem(ROLE_KEY)
    localStorage.removeItem(NAME_KEY)
  },
}
