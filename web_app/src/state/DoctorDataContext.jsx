import { createContext, useCallback, useContext, useRef, useState } from 'react'
import { ApiException } from '../core/apiClient'
import { doctorService } from '../services/doctorService'
import { entryService } from '../services/entryService'
import { patientService } from '../services/patientService'

// Mirrors mobile_app/lib/state/doctor_data_provider.dart (DoctorDataProvider)
// — same shape/conventions as PatientDataContext, but keyed off the
// doctor's own user id since every doctor-scoped endpoint
// (/doctors/{doctor_id}/...) takes that rather than a patient id. Holds
// roster + alerts (loaded together) plus per-patient detail state
// (profile/timeline/notes, loaded on demand when a roster/alert row opens).
const DoctorDataContext = createContext(null)

export function DoctorDataProvider({ children }) {
  const doctorIdRef = useRef(null)
  const [roster, setRoster] = useState([])
  const [alerts, setAlerts] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [loadError, setLoadError] = useState(null)

  const [selectedPatient, setSelectedPatient] = useState(null)
  const [selectedTimeline, setSelectedTimeline] = useState([]) // newest first, same as the patient app's own timeline
  const [selectedNotes, setSelectedNotes] = useState([])
  const [isLoadingDetail, setIsLoadingDetail] = useState(false)
  const [detailError, setDetailError] = useState(null)

  const unreviewedAlertCount = alerts.filter((a) => !a.reviewed).length

  const loadAll = useCallback(async (doctorId) => {
    doctorIdRef.current = doctorId
    setIsLoading(true)
    setLoadError(null)
    try {
      const [rosterRes, alertsRes] = await Promise.all([
        doctorService.getRoster(doctorId),
        doctorService.getAlerts(doctorId), // no ?reviewed filter — both screens need the full set
      ])
      setRoster(rosterRes)
      setAlerts(alertsRes)
    } catch (e) {
      setLoadError(e instanceof ApiException ? e.message : 'Could not load your patients right now.')
    } finally {
      setIsLoading(false)
    }
  }, [])

  const refreshRoster = useCallback(async () => {
    if (doctorIdRef.current == null) return
    try {
      setRoster(await doctorService.getRoster(doctorIdRef.current))
    } catch {
      // Silent — same convention as PatientDataContext.refreshTimeline: keep
      // whatever's already loaded rather than clobbering it with an error
      // state on a background pull-to-refresh.
    }
  }, [])

  const refreshAlerts = useCallback(async () => {
    if (doctorIdRef.current == null) return
    try {
      setAlerts(await doctorService.getAlerts(doctorIdRef.current))
    } catch {
      // Same convention as above.
    }
  }, [])

  // Marks an alert reviewed and updates it in place in the already-loaded
  // list. Deliberately does NOT refresh the roster — a roster row's
  // latest_risk_level/latest_reasoning reflect the patient's latest entry,
  // not alert-review state, so nothing there changes from this call. Lets
  // any error propagate to the caller (the Alerts screen shows it inline)
  // rather than swallowing it — unlike the background refreshes above, this
  // is a direct user action and should surface a failure.
  const reviewAlert = useCallback(async (alertId) => {
    const updated = await doctorService.reviewAlert(alertId)
    setAlerts((prev) => prev.map((a) => (a.id === alertId ? updated : a)))
  }, [])

  const loadPatientDetail = useCallback(async (patientId) => {
    setIsLoadingDetail(true)
    setDetailError(null)
    setSelectedPatient(null)
    setSelectedTimeline([])
    setSelectedNotes([])
    try {
      const [profileRes, timelineRes, notesRes] = await Promise.all([
        patientService.getPatient(patientId),
        entryService.getTimeline(patientId),
        patientService.getNotes(patientId),
      ])
      setSelectedPatient(profileRes)
      setSelectedTimeline(timelineRes)
      setSelectedNotes(notesRes)
    } catch (e) {
      setDetailError(e instanceof ApiException ? e.message : 'Could not load this patient right now.')
    } finally {
      setIsLoadingDetail(false)
    }
  }, [])

  // Adds a note and prepends it to the already-loaded list (newest-first,
  // matching GET /patients/{id}/notes' own ordering) rather than
  // re-fetching. Lets errors propagate — the caller (the add-note form)
  // shows them inline, same reasoning as reviewAlert above.
  const addNote = useCallback(async (patientId, noteText) => {
    const note = await patientService.addNote(patientId, noteText)
    setSelectedNotes((prev) => [note, ...prev])
  }, [])

  const reset = useCallback(() => {
    doctorIdRef.current = null
    setRoster([])
    setAlerts([])
    setSelectedPatient(null)
    setSelectedTimeline([])
    setSelectedNotes([])
    setIsLoading(false)
    setLoadError(null)
    setIsLoadingDetail(false)
    setDetailError(null)
  }, [])

  return (
    <DoctorDataContext.Provider
      value={{
        roster,
        alerts,
        unreviewedAlertCount,
        isLoading,
        loadError,
        loadAll,
        refreshRoster,
        refreshAlerts,
        reviewAlert,
        selectedPatient,
        selectedTimeline,
        selectedNotes,
        isLoadingDetail,
        detailError,
        loadPatientDetail,
        addNote,
        reset,
      }}
    >
      {children}
    </DoctorDataContext.Provider>
  )
}

export function useDoctorData() {
  const ctx = useContext(DoctorDataContext)
  if (!ctx) throw new Error('useDoctorData must be used within DoctorDataProvider')
  return ctx
}
