import { apiClient } from '../core/apiClient'

// GET/POST /admin/users, PATCH /admin/users/{id} — mirrors
// mobile_app/lib/services/admin_service.dart. One file, matching that
// file's one-file-per-role-workflow grouping (see context/conventions.md).
export const adminService = {
  getUsers() {
    return apiClient.get('/admin/users')
  },

  // Creates a user of any role. Reuses the backend's existing real
  // bcrypt-hashing flow (app.core.security.hash_password) — this just
  // sends the plaintext password over the API the same way login does; no
  // hashing happens client-side.
  createUser({ name, role, phoneOrEmail, password, languagePreference }) {
    return apiClient.post('/admin/users', {
      name,
      role,
      phone_or_email: phoneOrEmail,
      password,
      language_preference: languagePreference,
    })
  },

  // Partial edit — only the fields the backend actually supports
  // (name/role/phone_or_email/language_preference). No `status` field:
  // `users` has no such column and none was added — see
  // context/api-contracts.md / context/decisions-log.md.
  updateUser(userId, { name, role, phoneOrEmail, languagePreference }) {
    const body = {}
    if (name !== undefined) body.name = name
    if (role !== undefined) body.role = role
    if (phoneOrEmail !== undefined) body.phone_or_email = phoneOrEmail
    if (languagePreference !== undefined) body.language_preference = languagePreference
    return apiClient.patch(`/admin/users/${userId}`, body)
  },
}
