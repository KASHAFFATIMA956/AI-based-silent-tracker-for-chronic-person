import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ApiException } from '../core/apiClient'
import { messageService } from '../services/messageService'
import { useAuth } from '../state/AuthContext'

const POLL_INTERVAL_MS = 12000

// Direct-messaging chat thread between a patient (or their attendant) and
// their assigned doctor. Shared by both roles — a patient reaches this at
// /messages (title = their doctor's name), a doctor reaches it at
// /roster/:patientId/messages from a patient's detail screen (title = the
// patient's name, via screens/doctor/PatientMessagesScreen.jsx). One
// implementation since the chat UI itself doesn't differ by role; which
// bubbles render right-aligned is derived purely from
// `sender_user_id === the signed-in user's own id`. Lives at the top level
// of screens/ (not under patient/ or doctor/) since it's genuinely shared,
// mirroring mobile_app/lib/screens/messages_screen.dart's own placement.
// Added 2026-09-07 — see context/decisions-log.md.
//
// Polling, not websockets: this backend is REST-only with no existing
// websocket infrastructure (see context/conventions.md) — this component
// re-fetches GET /patients/{id}/messages on an interval while mounted.
// React Router unmounts a route's element on navigation away (unlike
// Flutter's IndexedStack tabs, which keep children alive), so the
// `useEffect` cleanup below genuinely stops polling once the screen is
// left — no extra visibility bookkeeping needed on this platform. Real-time
// push (websockets/SSE) is a possible future upgrade, not built this pass.
export function MessagesScreen({ patientId, title, backTo, backLabel }) {
  const { session } = useAuth()
  const navigate = useNavigate()
  const [messages, setMessages] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [loadError, setLoadError] = useState(null)
  const [draft, setDraft] = useState('')
  const [sending, setSending] = useState(false)
  const [sendError, setSendError] = useState(null)
  const listRef = useRef(null)

  const load = useCallback(
    async (showSpinner) => {
      if (showSpinner) {
        setIsLoading(true)
        setLoadError(null)
      }
      try {
        const list = await messageService.getMessages(patientId)
        const el = listRef.current
        const wasAtBottom = !el || el.scrollHeight - el.scrollTop - el.clientHeight < 40
        setMessages(list)
        if (wasAtBottom) {
          requestAnimationFrame(() => {
            if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight
          })
        }
      } catch (e) {
        // A background poll failure stays silent, same convention as
        // PatientDataContext.refreshTimeline — only a first-load failure
        // surfaces an error state, so a dropped poll never clobbers an
        // already-loaded thread.
        if (showSpinner) {
          setLoadError(e instanceof ApiException ? e.message : 'Could not load messages right now.')
        }
      } finally {
        if (showSpinner) setIsLoading(false)
      }
    },
    [patientId],
  )

  useEffect(() => {
    load(true)
    const id = setInterval(() => load(false), POLL_INTERVAL_MS)
    return () => clearInterval(id)
  }, [load])

  async function handleSend() {
    const text = draft.trim()
    if (!text || sending) return
    setSending(true)
    setSendError(null)
    try {
      const sent = await messageService.sendMessage(patientId, text)
      setMessages((prev) => [...prev, sent])
      setDraft('')
      requestAnimationFrame(() => {
        if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight
      })
    } catch (e) {
      setSendError(e instanceof ApiException ? e.message : 'Could not send this message. Try again.')
    } finally {
      setSending(false)
    }
  }

  function handleKeyDown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  return (
    <div style={{ padding: '32px 40px', maxWidth: 820, display: 'flex', flexDirection: 'column', height: '100vh', boxSizing: 'border-box' }}>
      {backTo && (
        <button
          className="rn-btn rn-btn-ghost"
          style={{ paddingLeft: 0, fontSize: 13, alignSelf: 'flex-start' }}
          onClick={() => navigate(backTo)}
        >
          ← {backLabel ?? 'Back'}
        </button>
      )}
      <h1 style={{ fontSize: 24, marginBottom: 18 }}>{title}</h1>

      <div
        ref={listRef}
        className="rn-card"
        style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 8, padding: 18 }}
      >
        {isLoading && messages.length === 0 && <p className="rn-muted">Loading…</p>}
        {loadError && messages.length === 0 && (
          <div>
            <p style={{ color: 'var(--rn-red)' }}>{loadError}</p>
            <button className="rn-btn rn-btn-secondary" onClick={() => load(true)}>
              Try again
            </button>
          </div>
        )}
        {!isLoading && !loadError && messages.length === 0 && (
          <p className="rn-muted">No messages yet. Say hello!</p>
        )}
        {messages.map((m) => (
          <MessageBubble key={m.id} message={m} isOwn={m.sender_user_id === session?.userId} />
        ))}
      </div>

      <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
        <textarea
          className="rn-input"
          style={{ minHeight: 44, maxHeight: 120, resize: 'none' }}
          placeholder="Type a message…"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={handleKeyDown}
        />
        <button className="rn-btn rn-btn-primary" onClick={handleSend} disabled={sending || !draft.trim()}>
          {sending ? 'Sending…' : 'Send'}
        </button>
      </div>
      {sendError && <p style={{ color: 'var(--rn-red)', fontSize: 13, marginTop: 6 }}>{sendError}</p>}
    </div>
  )
}

function MessageBubble({ message, isOwn }) {
  const bg = isOwn ? 'var(--rn-accent)' : 'var(--rn-accent-100)'
  const fg = isOwn ? 'var(--rn-surface)' : 'var(--rn-text)'
  const roleLabel = message.sender_role === 'doctor' ? 'Doctor' : message.sender_role === 'attendant' ? 'Attendant' : 'Patient'
  const timestamp = new Date(message.created_at).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })

  return (
    <div style={{ display: 'flex', justifyContent: isOwn ? 'flex-end' : 'flex-start' }}>
      <div
        style={{
          maxWidth: '75%',
          background: bg,
          color: fg,
          borderRadius: 14,
          borderBottomRightRadius: isOwn ? 2 : 14,
          borderBottomLeftRadius: isOwn ? 14 : 2,
          padding: '10px 14px',
        }}
      >
        {!isOwn && (
          <div style={{ fontSize: 11, fontWeight: 600, opacity: 0.75, marginBottom: 3 }}>
            {message.sender_name ?? roleLabel}
          </div>
        )}
        <div style={{ fontSize: 14.5 }}>{message.content}</div>
        <div style={{ fontSize: 10.5, opacity: 0.65, marginTop: 3 }}>{timestamp}</div>
      </div>
    </div>
  )
}
