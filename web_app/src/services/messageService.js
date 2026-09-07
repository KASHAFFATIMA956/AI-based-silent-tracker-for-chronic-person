import { apiClient } from '../core/apiClient'

// GET/POST /patients/{patient_id}/messages — direct messaging between a
// patient (or their attendant) and their assigned doctor. Added
// 2026-09-07 — see context/api-contracts.md. Mirrors
// mobile_app/lib/services/message_service.dart. Kept in its own file
// rather than patientService.js since it's a large enough standalone
// feature (a whole polled chat screen) to warrant one, mirroring the
// backend's own separate app/routers/messages.py.
export const messageService = {
  getMessages(patientId) {
    return apiClient.get(`/patients/${patientId}/messages`)
  },

  sendMessage(patientId, content) {
    return apiClient.post(`/patients/${patientId}/messages`, { content })
  },
}
