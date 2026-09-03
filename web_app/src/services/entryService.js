import { apiClient } from '../core/apiClient'

// POST /entries, POST /entries/{id}/audio, GET /entries/{patient_id}/timeline
// — mirrors mobile_app/lib/services/entry_service.dart. `submitEntry`'s
// request shape matches app/schemas/entry.py's EntryCreate exactly, same
// null-omission behavior (only send a field when it has a value).
export const entryService = {
  submitEntry({
    patientId,
    entryType,
    rawTranscript,
    sleepValue,
    energyValue,
    moodValue,
    appetiteValue,
    mobilityValue,
    weightValue,
    medicineStatus,
    symptomIds = [],
  }) {
    const body = {
      patient_id: patientId,
      entry_type: entryType,
      medicine_status: medicineStatus,
      symptom_ids: symptomIds,
    }
    if (rawTranscript !== undefined && rawTranscript !== null) body.raw_transcript = rawTranscript
    if (sleepValue !== undefined && sleepValue !== null) body.sleep_value = sleepValue
    if (energyValue !== undefined && energyValue !== null) body.energy_value = energyValue
    if (moodValue !== undefined && moodValue !== null) body.mood_value = moodValue
    if (appetiteValue !== undefined && appetiteValue !== null) body.appetite_value = appetiteValue
    if (mobilityValue !== undefined && mobilityValue !== null) body.mobility_value = mobilityValue
    if (weightValue !== undefined && weightValue !== null) body.weight_value = weightValue
    return apiClient.post('/entries', body)
  },

  // POST /entries/{entry_id}/audio — attaches a raw Voice Diary recording
  // to an already-created voice entry for backend acoustic-signal
  // analysis. See context/api-contracts.md and context/decisions-log.md
  // ("Web voice capture: Web Speech API + MediaRecorder") for how the web
  // recording (a webm/opus Blob from MediaRecorder) reaches this call —
  // callers should treat failure here as non-fatal, same contract as the
  // Flutter app's uploadAudio/attachAudio.
  uploadAudio(entryId, audioBlob, filename = 'voice-sample.webm') {
    const formData = new FormData()
    formData.append('audio_file', audioBlob, filename)
    return apiClient.postForm(`/entries/${entryId}/audio`, formData)
  },

  getTimeline(patientId) {
    return apiClient.get(`/entries/${patientId}/timeline`)
  },
}
