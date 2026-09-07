import { apiClient } from '../core/apiClient'

// GET /patients/{id}, GET /patients/{id}/symptom-checklist,
// GET+POST /patients/{id}/notes — mirrors
// mobile_app/lib/services/patient_service.dart. The notes methods are
// doctor/admin-only backend-side (RBAC enforced server-side, not here) —
// kept in this file rather than doctorService.js since api-contracts.md
// groups /patients/{id}/notes under "Patients", same URL prefix as this
// file's other two methods, same reasoning as the Flutter file's own doc
// comment. Added 2026-08-29 (React doctor-role pass) — the doctor role was
// previously the reason these were left out.
export const patientService = {
  getPatient(patientId) {
    return apiClient.get(`/patients/${patientId}`)
  },

  getSymptomChecklist(patientId) {
    return apiClient.get(`/patients/${patientId}/symptom-checklist`)
  },

  getNotes(patientId) {
    return apiClient.get(`/patients/${patientId}/notes`)
  },

  addNote(patientId, noteText) {
    return apiClient.post(`/patients/${patientId}/notes`, { note_text: noteText })
  },
}
