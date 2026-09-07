import { createContext, useCallback, useContext, useState } from 'react'
import { ApiException } from '../core/apiClient'
import { adminService } from '../services/adminService'

// Mirrors mobile_app/lib/state/admin_data_provider.dart (AdminDataProvider)
// — same shape/conventions as DoctorDataContext/PatientDataContext: one
// `users` list, `loadAll()` populates it once per sign-in,
// `createUser`/`updateUser` update it in place afterward rather than
// re-fetching the whole roster (same convention as
// DoctorDataContext.reviewAlert/addNote).
const AdminDataContext = createContext(null)

export function AdminDataProvider({ children }) {
  const [users, setUsers] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [loadError, setLoadError] = useState(null)

  const loadAll = useCallback(async () => {
    setIsLoading(true)
    setLoadError(null)
    try {
      setUsers(await adminService.getUsers())
    } catch (e) {
      setLoadError(e instanceof ApiException ? e.message : 'Could not load the people list right now.')
    } finally {
      setIsLoading(false)
    }
  }, [])

  const refresh = useCallback(async () => {
    try {
      setUsers(await adminService.getUsers())
    } catch {
      // Silent — same convention as the sibling contexts' background
      // refreshes: keep whatever's already shown rather than clobbering it
      // with an error state.
    }
  }, [])

  // Lets errors propagate to the caller (the create/edit form shows them
  // inline) — a direct user action, unlike the silent background refresh
  // above, same distinction DoctorDataContext draws.
  const createUser = useCallback(async (input) => {
    const created = await adminService.createUser(input)
    setUsers((prev) => [...prev, created])
    return created
  }, [])

  // Replaces the edited row in place so the list reflects the backend's
  // actual computed linked_summary/diagnosis for the new role, not a
  // locally-guessed value.
  const updateUser = useCallback(async (userId, input) => {
    const updated = await adminService.updateUser(userId, input)
    setUsers((prev) => {
      const idx = prev.findIndex((u) => u.id === userId)
      if (idx === -1) return [...prev, updated]
      const next = [...prev]
      next[idx] = updated
      return next
    })
    return updated
  }, [])

  const reset = useCallback(() => {
    setUsers([])
    setIsLoading(false)
    setLoadError(null)
  }, [])

  return (
    <AdminDataContext.Provider value={{ users, isLoading, loadError, loadAll, refresh, createUser, updateUser, reset }}>
      {children}
    </AdminDataContext.Provider>
  )
}

export function useAdminData() {
  const ctx = useContext(AdminDataContext)
  if (!ctx) throw new Error('useAdminData must be used within AdminDataProvider')
  return ctx
}
