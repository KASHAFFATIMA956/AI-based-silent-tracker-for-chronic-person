import { useEffect, useRef } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { AdminShell } from './components/AdminShell'
import { DoctorShell } from './components/DoctorShell'
import { PatientShell } from './components/PatientShell'
import { PeopleScreen } from './screens/admin/PeopleScreen'
import { UserFormScreen } from './screens/admin/UserFormScreen'
import { LoginScreen } from './screens/auth/LoginScreen'
import { AlertsScreen } from './screens/doctor/AlertsScreen'
import { PatientDetailScreen } from './screens/doctor/PatientDetailScreen'
import { PatientRosterScreen } from './screens/doctor/PatientRosterScreen'
import { PlaceholderScreen } from './screens/PlaceholderScreen'
import { HomeScreen } from './screens/patient/HomeScreen'
import { ProfileScreen } from './screens/patient/ProfileScreen'
import { QuickCheckinScreen } from './screens/patient/QuickCheckinScreen'
import { ResultScreen } from './screens/patient/ResultScreen'
import { TimelineScreen } from './screens/patient/TimelineScreen'
import { VoiceDiaryScreen } from './screens/patient/VoiceDiaryScreen'
import { WeeklyDigestScreen } from './screens/patient/WeeklyDigestScreen'
import { useAdminData } from './state/AdminDataContext'
import { AUTH_STATUS, useAuth } from './state/AuthContext'
import { useDoctorData } from './state/DoctorDataContext'
import { useLanguage } from './state/LanguageContext'
import { usePatientData } from './state/PatientDataContext'

// The ONLY place that decides which screens a signed-in user can reach —
// and it decides purely from `session.role` (sourced from the backend
// JWT), never from which login form was used or any other user choice.
// Mirrors mobile_app/lib/screens/root_router.dart exactly, including the
// once-per-sign-in data-load guard and its real fix (context/decisions-log.md,
// 2026-08-29 entry: the original Flutter guard used a boolean living for
// the whole app run, so a second sign-in after logout never reloaded —
// this version keys the guard on patientId + resets it on sign-out from the
// start, avoiding that bug class rather than reproducing and re-fixing it).
export default function App() {
  const { status, session } = useAuth()
  const { loadAll, reset } = usePatientData()
  const doctorData = useDoctorData()
  const adminData = useAdminData()
  const { setFromAccountPreference } = useLanguage()
  const loadedForPatientId = useRef(null)
  const loadedForDoctorId = useRef(null)
  const loadedForAdminId = useRef(null)

  useEffect(() => {
    if (status !== AUTH_STATUS.SIGNED_IN || session?.patientId == null) return
    if (loadedForPatientId.current === session.patientId) return
    loadedForPatientId.current = session.patientId
    setFromAccountPreference(session.languagePreference)
    loadAll(session.patientId)
  }, [status, session, loadAll, setFromAccountPreference])

  // Doctor role's own data-load guard — same keyed-on-id shape as the
  // patient effect above, and for the same reason: mobile_app's doctor
  // build (context/decisions-log.md, 2026-08-29) found a real bug where a
  // once-per-app-launch boolean guard meant switching accounts (logout,
  // log in as a different doctor) never reloaded, leaving the previous
  // doctor's roster/alerts stale. Keying this on session.userId (not a
  // fire-once boolean) means a second sign-in as a DIFFERENT doctor
  // re-triggers loadAll automatically — the same class of bug can't recur
  // here by construction, not because it was re-discovered and patched.
  useEffect(() => {
    if (status !== AUTH_STATUS.SIGNED_IN || session?.role !== 'doctor') return
    if (loadedForDoctorId.current === session.userId) return
    loadedForDoctorId.current = session.userId
    doctorData.loadAll(session.userId)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status, session])

  // Admin role's own data-load guard — same keyed-on-userId shape as the
  // doctor effect above, for the same reason: GET /admin/users takes no
  // param (it's a flat all-users list, not scoped per admin), but the
  // guard is still keyed on session.userId rather than a fire-once
  // boolean so an account switch (logout, sign in as a different admin,
  // or as a different role entirely and back) reliably reloads rather than
  // leaving a previous session's list stale — same bug class
  // mobile_app/lib/screens/root_router.dart found and fixed for the
  // doctor role (see context/decisions-log.md), avoided here by
  // construction from the start.
  useEffect(() => {
    if (status !== AUTH_STATUS.SIGNED_IN || session?.role !== 'admin') return
    if (loadedForAdminId.current === session.userId) return
    loadedForAdminId.current = session.userId
    adminData.loadAll()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status, session])

  useEffect(() => {
    if (status === AUTH_STATUS.SIGNED_OUT) {
      loadedForPatientId.current = null
      loadedForDoctorId.current = null
      loadedForAdminId.current = null
      reset()
      doctorData.reset()
      adminData.reset()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status])

  if (status === AUTH_STATUS.UNKNOWN) {
    return <SplashScreen />
  }

  if (status === AUTH_STATUS.SIGNED_OUT) {
    return (
      <Routes>
        <Route path="*" element={<LoginScreen />} />
      </Routes>
    )
  }

  if (session.role === 'doctor') {
    return (
      <Routes>
        <Route element={<DoctorShell />}>
          {/* Deliberately NOT "/patients" or "/alerts" — vite.config.js's dev-server
              proxy forwards those exact path prefixes straight to the FastAPI
              backend (see context/decisions-log.md, "web app CORS/proxy decision").
              Client-side <Link>/navigate() nav never hits the proxy (React Router
              intercepts before a real HTTP request happens), so this bug only
              shows up on a full page load/refresh/bookmark at the URL — caught
              during this session's own real-browser verification, not by code
              review; see context/decisions-log.md for the full writeup. */}
          <Route path="/roster" element={<PatientRosterScreen />} />
          <Route path="/roster/:patientId" element={<PatientDetailScreen />} />
          <Route path="/notifications" element={<AlertsScreen />} />
          <Route path="*" element={<Navigate to="/roster" replace />} />
        </Route>
      </Routes>
    )
  }

  if (session.role === 'admin') {
    return (
      <Routes>
        <Route element={<AdminShell />}>
          {/* Deliberately NOT "/admin" — vite.config.js's dev-server proxy
              forwards that exact path prefix straight to the FastAPI
              backend (see the doctor role's own "/roster" vs "/patients"
              note above, and context/decisions-log.md for the original bug
              this pattern avoids). "/people" doesn't collide with any
              proxied prefix (/auth, /patients, /entries, /doctors, /alerts,
              /admin, /health) — verified against vite.config.js before
              picking it, not just avoiding an existing screen name. */}
          <Route path="/people" element={<PeopleScreen />} />
          <Route path="/people/new" element={<UserFormScreen />} />
          <Route path="/people/:userId/edit" element={<UserFormScreen />} />
          <Route path="*" element={<Navigate to="/people" replace />} />
        </Route>
      </Routes>
    )
  }

  const isPatientOrAttendant = session.role === 'patient' || session.role === 'attendant'

  if (!isPatientOrAttendant) {
    // Anything left (shouldn't happen with real backend role values, but
    // fail gracefully rather than assume): same placeholder as before.
    return (
      <Routes>
        <Route path="*" element={<PlaceholderScreen />} />
      </Routes>
    )
  }

  if (session.patientId == null) {
    // A patient/attendant account with no linked Patient row yet —
    // shouldn't happen with real seed data, but fail visibly.
    return <UnlinkedAccountScreen />
  }

  return (
    <Routes>
      <Route element={<PatientShell />}>
        <Route path="/home" element={<HomeScreen />} />
        <Route path="/voice" element={<VoiceDiaryScreen />} />
        <Route path="/check-in" element={<QuickCheckinScreen />} />
        <Route path="/result" element={<ResultScreen />} />
        <Route path="/timeline" element={<TimelineScreen />} />
        <Route path="/digest" element={<WeeklyDigestScreen />} />
        <Route path="/profile" element={<ProfileScreen />} />
        <Route path="*" element={<Navigate to="/home" replace />} />
      </Route>
    </Routes>
  )
}

function SplashScreen() {
  return (
    <div style={{ display: 'grid', placeItems: 'center', height: '100vh' }}>
      <div className="rn-muted">Loading RozNoor…</div>
    </div>
  )
}

function UnlinkedAccountScreen() {
  const { logout } = useAuth()
  return (
    <div style={{ display: 'grid', placeItems: 'center', height: '100vh', padding: 24, textAlign: 'center' }}>
      <div>
        <p>This account isn't linked to a patient record yet.<br />Ask your clinic to finish setting up your profile.</p>
        <button className="rn-btn rn-btn-secondary" onClick={logout}>
          Log out
        </button>
      </div>
    </div>
  )
}
