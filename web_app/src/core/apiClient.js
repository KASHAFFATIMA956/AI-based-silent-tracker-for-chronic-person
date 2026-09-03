import { API_BASE_URL } from './appConfig'
import { tokenStorage } from './tokenStorage'

/// Thin, self-contained failure type every service call throws on non-2xx —
/// screens catch this and show `.message` rather than a raw fetch error.
/// Mirrors mobile_app/lib/core/api_client.dart's ApiException exactly.
export class ApiException extends Error {
  constructor(statusCode, message) {
    super(message)
    this.statusCode = statusCode
    this.message = message
  }
}

/// One shared request function, attaching `Authorization: Bearer <token>`
/// to every request that has a stored session — see
/// context/conventions.md ("API client pattern"). No screen or service
/// ever reads tokenStorage directly to build a header; they call apiRequest
/// (or apiRequestForm, for multipart) and this does it once. Mirrors
/// ApiClient.instance.dio's single-interceptor design in the Flutter app.
async function apiRequest(path, { method = 'GET', body, isForm = false } = {}) {
  const token = tokenStorage.readToken()
  const headers = {}
  if (!isForm) headers['Content-Type'] = 'application/json'
  if (token) headers['Authorization'] = `Bearer ${token}`

  let response
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : isForm ? body : JSON.stringify(body),
    })
  } catch {
    // Covers network failure / connection refused / CORS-style rejection —
    // fetch() throws a plain TypeError for all of these, with no
    // distinguishing detail, same limitation Dio's connectionError branch
    // works around with its own message (see the Flutter equivalent).
    throw new ApiException(null, 'Could not reach RozNoor. Check your connection and try again.')
  }

  let data = null
  const text = await response.text()
  if (text) {
    try {
      data = JSON.parse(text)
    } catch {
      data = null
    }
  }

  if (!response.ok) {
    const message =
      data && typeof data === 'object' && data.detail
        ? String(data.detail)
        : `Request failed (${response.status})`
    throw new ApiException(response.status, message)
  }

  return data
}

export const apiClient = {
  get: (path) => apiRequest(path, { method: 'GET' }),
  post: (path, body) => apiRequest(path, { method: 'POST', body }),
  patch: (path, body) => apiRequest(path, { method: 'PATCH', body }),
  postForm: (path, formData) => apiRequest(path, { method: 'POST', body: formData, isForm: true }),
}
