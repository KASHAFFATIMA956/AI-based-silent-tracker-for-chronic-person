import { apiClient } from '../core/apiClient'

// GET /doctors/{doctor_id}/patients, GET /doctors/{doctor_id}/alerts,
// POST /alerts/{alert_id}/review — mirrors
// mobile_app/lib/services/doctor_service.dart. Grouped in one file (rather
// than a separate one for /alerts) since all three are one coherent
// doctor-workflow surface, same reasoning as the Flutter file's own doc
// comment (which itself mirrors app/routers/doctors.py's two-router-one-file
// grouping on the backend).
export const doctorService = {
  getRoster(doctorId) {
    return apiClient.get(`/doctors/${doctorId}/patients`)
  },

  getAlerts(doctorId, { reviewed } = {}) {
    const query = reviewed === undefined ? '' : `?reviewed=${reviewed}`
    return apiClient.get(`/doctors/${doctorId}/alerts${query}`)
  },

  reviewAlert(alertId) {
    return apiClient.post(`/alerts/${alertId}/review`)
  },
}
