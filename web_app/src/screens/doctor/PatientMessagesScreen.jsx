import { useParams } from 'react-router-dom'
import { useDoctorData } from '../../state/DoctorDataContext'
import { MessagesScreen } from '../MessagesScreen'

// Doctor's per-patient message thread, reached from PatientDetailScreen's
// "Messages" button. Looks the patient's name up from already-loaded
// roster/alerts data — same "no name field on GET /patients/{id}, and no
// per-id fetch either" workaround PatientDetailScreen.jsx already uses
// (see context/decisions-log.md) — rather than fetching it separately.
export function DoctorPatientMessagesScreen() {
  const { patientId } = useParams()
  const id = Number(patientId)
  const data = useDoctorData()

  const rosterMatch = data.roster.find((p) => p.patient_id === id)
  const alertMatch = data.alerts.find((a) => a.patient_id === id)
  const patientName = rosterMatch?.name ?? alertMatch?.patient_name ?? `Patient #${id}`

  return <MessagesScreen patientId={id} title={patientName} backTo={`/roster/${id}`} backLabel="Back to patient" />
}
