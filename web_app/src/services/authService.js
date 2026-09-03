import { apiClient } from '../core/apiClient'

// Wraps POST /auth/login and GET /auth/me — mirrors
// mobile_app/lib/services/auth_service.dart exactly (same two endpoints,
// same shaping into a plain session object). Does NOT re-implement any
// auth logic; that's entirely the backend's job.
export const authService = {
  async login(phoneOrEmail, password) {
    const data = await apiClient.post('/auth/login', {
      phone_or_email: phoneOrEmail,
      password,
    })
    return {
      token: data.access_token,
      userId: data.user_id,
      role: data.role,
      name: data.name,
    }
  },

  // Fetches the caller's own identity, including patient_id — called right
  // after login, and on app-start when a stored token is found, so the
  // session always carries a resolved patient_id before any patient-scoped
  // screen tries to use it. See context/api-contracts.md.
  async fetchMe(current) {
    const data = await apiClient.get('/auth/me')
    return {
      ...current,
      userId: data.id,
      role: data.role,
      name: data.name,
      patientId: data.patient_id ?? null,
      languagePreference: data.language_preference ?? null,
    }
  },
}
