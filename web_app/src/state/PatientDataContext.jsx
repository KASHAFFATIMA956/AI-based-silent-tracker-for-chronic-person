import { createContext, useCallback, useContext, useRef, useState } from 'react'
import { ApiException } from '../core/apiClient'
import { entryService } from '../services/entryService'
import { patientService } from '../services/patientService'

// Mirrors mobile_app/lib/state/patient_data_provider.dart. Holds every
// piece of "real" patient data the patient screens render — profile,
// symptom checklist, and timeline. One provider shared across the whole
// patient area so submitting an entry on Voice Diary / Quick Check-in
// immediately updates what Home/Timeline/Weekly Digest show, without each
// screen re-fetching independently.
const PatientDataContext = createContext(null)

export function PatientDataProvider({ children }) {
  const patientIdRef = useRef(null)
  const [profile, setProfile] = useState(null)
  const [symptomChecklist, setSymptomChecklist] = useState([])
  const [timeline, setTimeline] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [loadError, setLoadError] = useState(null)

  const latestEntry = timeline.length === 0 ? null : timeline[0]

  const loadAll = useCallback(async (patientId) => {
    patientIdRef.current = patientId
    setIsLoading(true)
    setLoadError(null)
    try {
      const [profileRes, checklistRes, timelineRes] = await Promise.all([
        patientService.getPatient(patientId),
        patientService.getSymptomChecklist(patientId),
        entryService.getTimeline(patientId),
      ])
      setProfile(profileRes)
      setSymptomChecklist(checklistRes)
      setTimeline(timelineRes)
    } catch (e) {
      setLoadError(e instanceof ApiException ? e.message : 'Could not load your data right now.')
    } finally {
      setIsLoading(false)
    }
  }, [])

  const refreshTimeline = useCallback(async () => {
    if (patientIdRef.current == null) return
    try {
      const t = await entryService.getTimeline(patientIdRef.current)
      setTimeline(t)
    } catch {
      // Timeline refresh failures stay silent here — the caller shows its
      // own retry affordance; this just avoids clobbering already-loaded
      // data with an error state on a background refresh.
    }
  }, [])

  // Submits an entry, then refreshes the timeline (and profile, since
  // day_count/baseline_stage may have advanced server-side) so
  // Home/Timeline/Digest reflect it immediately. Returns the created entry
  // (with its risk_result) for the Result screen to display.
  const submitEntry = useCallback(async (params) => {
    if (patientIdRef.current == null) {
      throw new Error('PatientDataProvider.loadAll must be called first')
    }
    const entry = await entryService.submitEntry({ patientId: patientIdRef.current, ...params })
    await refreshTimeline()
    try {
      setProfile(await patientService.getPatient(patientIdRef.current))
    } catch {
      // Non-fatal — the just-submitted entry's own result still returns
      // below even if this refresh fails.
    }
    return entry
  }, [refreshTimeline])

  // Attaches a locally-recorded Voice Diary audio Blob to an
  // already-submitted voice entry (POST /entries/{id}/audio), then
  // refreshes the timeline so the (possibly acoustic-signal-updated)
  // risk_result shows everywhere. Best-effort by design, same soft-fail
  // contract as PatientDataProvider.attachAudio in the Flutter app — a
  // failure here must never surface as a broken entry, since the entry and
  // its transcript-based risk_result already exist and are valid on their
  // own. Returns the updated entry on success, or null on any failure.
  const attachAudio = useCallback(async (entryId, audioBlob) => {
    try {
      const updated = await entryService.uploadAudio(entryId, audioBlob)
      await refreshTimeline()
      if (patientIdRef.current != null) {
        try {
          setProfile(await patientService.getPatient(patientIdRef.current))
        } catch {
          // Non-fatal, same as submitEntry's profile refresh above.
        }
      }
      return updated
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn(`attachAudio failed (entry ${entryId}):`, e)
      return null
    }
  }, [refreshTimeline])

  const reset = useCallback(() => {
    patientIdRef.current = null
    setProfile(null)
    setSymptomChecklist([])
    setTimeline([])
    setIsLoading(false)
    setLoadError(null)
  }, [])

  return (
    <PatientDataContext.Provider
      value={{
        profile,
        symptomChecklist,
        timeline,
        latestEntry,
        isLoading,
        loadError,
        loadAll,
        refreshTimeline,
        submitEntry,
        attachAudio,
        reset,
      }}
    >
      {children}
    </PatientDataContext.Provider>
  )
}

export function usePatientData() {
  const ctx = useContext(PatientDataContext)
  if (!ctx) throw new Error('usePatientData must be used within PatientDataProvider')
  return ctx
}
