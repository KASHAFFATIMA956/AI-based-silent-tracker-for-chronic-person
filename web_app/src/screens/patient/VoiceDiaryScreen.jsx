import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BilingualText } from '../../components/BilingualText'
import { ApiException } from '../../core/apiClient'
import { useLanguage } from '../../state/LanguageContext'
import { usePatientData } from '../../state/PatientDataContext'

// Voice Diary — POST /entries with entry_type=voice + raw_transcript, then
// (best-effort) POST /entries/{id}/audio. Content/flow source is the
// prototype's p-voice screen; the underlying speech tech is deliberately
// NOT the same as mobile_app's — see the module-level notes below and
// context/decisions-log.md ("Web voice capture: Web Speech API +
// MediaRecorder") for the full write-up of what differs and why.
//
// SPEECH-TO-TEXT: the browser's Web Speech API (SpeechRecognition /
// webkitSpeechRecognition), NOT speech_to_text (mobile_app's on-device
// package). Real, flagged differences from the Flutter app:
//   - Browser support is uneven: works in Chrome/Edge (webkit-prefixed),
//     NOT supported in Firefox, inconsistent in Safari. mobile_app's
//     speech_to_text instead uses each OS's own always-present speech
//     engine, so mobile has no equivalent "unsupported browser" gap.
//   - Chrome's implementation sends audio to Google's servers for
//     recognition — it is NOT on-device the way mobile_app's comment
//     describes speech_to_text as being. A genuine privacy-model
//     difference, not just an availability one.
//   - Requires a secure context (HTTPS) in production; localhost is
//     exempted (what this session's dev-server verification relies on).
//     A real deployment of this web app needs HTTPS for Voice Diary to
//     work at all — flagged here and in context/decisions-log.md.
//   - No raw-audio export from the recognizer itself — same constraint
//     speech_to_text has (see mobile_app's own comment on this), which is
//     why acoustic-analysis capture below is a SEPARATE MediaRecorder
//     session, mirroring mobile's AudioRecorderService + record package
//     split.
//
// ACOUSTIC-ANALYSIS AUDIO CAPTURE: MediaRecorder (getUserMedia), run
// SEQUENTIALLY after SpeechRecognition ends — same sequenced design as
// mobile_app's 2026-08-27 mic-contention fix (see
// context/decisions-log.md), applied here proactively rather than
// discovered the same way. Browsers may not actually share this specific
// contention risk (Chrome's SpeechRecognition doesn't request the mic via
// getUserMedia the way MediaRecorder does, so the two may not compete for
// the same OS-level resource at all) — this was NOT verified either way.
// Sequencing was kept anyway to mirror the already-verified, working
// mobile design rather than risk re-discovering the same class of bug on
// a different platform. The recorded format (audio/webm;codecs=opus, or
// whatever MediaRecorder.isTypeSupported picks) IS accepted by the
// backend (`POST /entries/{id}/audio` documents webm as a supported
// format — see context/api-contracts.md) — acoustic-analysis audio upload
// IS feasible on web, not skipped.
const FOLLOW_UP_SAMPLE_MS = 6000

function getSpeechRecognitionCtor() {
  return window.SpeechRecognition || window.webkitSpeechRecognition || null
}

export function VoiceDiaryScreen() {
  const navigate = useNavigate()
  const { speechLocaleId, isRomanUrdu } = useLanguage()
  const { submitEntry, attachAudio } = usePatientData()

  const recognitionRef = useRef(null)
  const mediaStreamRef = useRef(null)
  const mediaRecorderRef = useRef(null)
  const recordedChunksRef = useRef([])
  const followUpTriggeredRef = useRef(false)

  const [speechSupported] = useState(() => getSpeechRecognitionCtor() !== null)
  const [typeInstead, setTypeInstead] = useState(() => getSpeechRecognitionCtor() === null)
  const [listening, setListening] = useState(false)
  const [transcript, setTranscript] = useState('')
  const [typedText, setTypedText] = useState('')
  const [capturingSample, setCapturingSample] = useState(false)
  const [recordedBlob, setRecordedBlob] = useState(null)
  const [submitting, setSubmitting] = useState(false)
  const [lastError, setLastError] = useState(null)
  const [submitError, setSubmitError] = useState(null)

  useEffect(() => {
    return () => {
      recognitionRef.current?.stop()
      mediaStreamRef.current?.getTracks().forEach((t) => t.stop())
    }
  }, [])

  function buildRecognition() {
    const Ctor = getSpeechRecognitionCtor()
    if (!Ctor) return null
    const recognition = new Ctor()
    recognition.lang = speechLocaleId
    recognition.interimResults = true
    recognition.continuous = true
    recognition.onresult = (event) => {
      let combined = ''
      for (let i = 0; i < event.results.length; i++) {
        combined += event.results[i][0].transcript
      }
      setTranscript(combined)
    }
    recognition.onerror = (event) => {
      setLastError(event.error)
      setListening(false)
    }
    recognition.onend = () => {
      setListening(false)
      captureFollowUpSampleOnce()
    }
    return recognition
  }

  async function toggleListening() {
    if (listening) {
      recognitionRef.current?.stop()
      // onend fires from this too, but async with no ordering guarantee —
      // same double-call-site pattern (and same reasoning) as mobile_app's
      // voice_diary_screen.dart _toggleListening().
      captureFollowUpSampleOnce()
      return
    }
    setTranscript('')
    setRecordedBlob(null)
    setLastError(null)
    followUpTriggeredRef.current = false
    const recognition = buildRecognition()
    if (!recognition) {
      setTypeInstead(true)
      return
    }
    recognitionRef.current = recognition
    try {
      recognition.start()
      setListening(true)
    } catch (e) {
      setLastError(String(e))
      setListening(false)
    }
  }

  // Sequential audio capture for acoustic analysis — only ever called after
  // SpeechRecognition has released the mic (see the two call sites above),
  // mirroring mobile_app's _captureFollowUpAudioSampleOnce(). Best-effort
  // throughout: any failure just leaves recordedBlob null — Voice Diary's
  // transcript-and-submit path is completely unaffected either way.
  async function captureFollowUpSampleOnce() {
    if (followUpTriggeredRef.current) return
    followUpTriggeredRef.current = true
    setCapturingSample(true)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      mediaStreamRef.current = stream
      const mimeType = ['audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus'].find(
        (t) => window.MediaRecorder && MediaRecorder.isTypeSupported(t),
      )
      const recorder = mimeType ? new MediaRecorder(stream, { mimeType }) : new MediaRecorder(stream)
      mediaRecorderRef.current = recorder
      recordedChunksRef.current = []
      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) recordedChunksRef.current.push(e.data)
      }
      const stopped = new Promise((resolve) => {
        recorder.onstop = resolve
      })
      recorder.start()
      await new Promise((resolve) => setTimeout(resolve, FOLLOW_UP_SAMPLE_MS))
      recorder.stop()
      await stopped
      stream.getTracks().forEach((t) => t.stop())
      const blob = new Blob(recordedChunksRef.current, { type: recorder.mimeType || 'audio/webm' })
      setRecordedBlob(blob)
    } catch (e) {
      // No mic permission, no MediaRecorder support, etc. — best-effort,
      // same soft-fail contract as mobile_app's AudioRecorderService.
      // eslint-disable-next-line no-console
      console.warn('Follow-up audio sample capture failed:', e)
    } finally {
      setCapturingSample(false)
    }
  }

  const finalTranscript = (typeInstead ? typedText : transcript).trim()
  // Blocked while listening/capturing, same reasoning as mobile_app's
  // canAnalyze fix (context/decisions-log.md, 2026-08-28 entry): the button
  // must not be tappable until the follow-up capture sequence has actually
  // had the chance to run and finish.
  const canAnalyze = finalTranscript.length > 0 && !submitting && !capturingSample && !listening

  async function handleAnalyze() {
    if (!canAnalyze) return
    setSubmitting(true)
    setSubmitError(null)
    try {
      let entry = await submitEntry({
        entryType: 'voice',
        rawTranscript: finalTranscript,
        medicineStatus: 'taken',
      })
      if (recordedBlob) {
        const updated = await attachAudio(entry.id, recordedBlob)
        if (updated) entry = updated
      }
      navigate('/result', { state: { entry } })
    } catch (e) {
      setSubmitError(e instanceof ApiException ? e.message : 'Something went wrong. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  function handleReset() {
    setTranscript('')
    setTypedText('')
    setRecordedBlob(null)
  }

  return (
    <div style={{ padding: '32px 40px', maxWidth: 900 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <BilingualText as="h1" en="Tell us in your own words" ur="Apni baat kahiye" style={{ fontSize: 28 }} />
      </div>
      <p className="rn-muted" style={{ marginTop: 4 }}>Recognition locale: {speechLocaleId}</p>

      {!typeInstead && (
        <div className="rn-card" style={{ marginTop: 20, padding: '32px 26px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16 }}>
          <button
            onClick={toggleListening}
            disabled={capturingSample}
            style={{
              width: 130,
              height: 130,
              borderRadius: '50%',
              border: '1.5px solid var(--rn-accent)',
              background: listening || capturingSample ? 'var(--rn-accent-100)' : 'transparent',
              color: 'var(--rn-accent)',
              display: 'grid',
              placeItems: 'center',
              cursor: capturingSample ? 'not-allowed' : 'pointer',
            }}
          >
            <MicGlyph listening={listening} />
          </button>
          <div style={{ fontSize: 17, fontWeight: 600, fontFamily: 'Space Grotesk, sans-serif' }}>
            {capturingSample ? 'Capturing voice sample for analysis…' : listening ? 'Listening…' : 'Tap to speak'}
          </div>
          {capturingSample && (
            <p className="rn-muted" style={{ fontSize: 11, textAlign: 'center', maxWidth: 420 }}>
              A short voice sample for the acoustic signal (fatigue/breathlessness) is recorded right after you finish
              speaking — this is separate from the transcript below.
            </p>
          )}
          {lastError && (
            <p style={{ color: 'var(--rn-red)', fontSize: 12, fontWeight: 600, textAlign: 'center' }}>
              Recognition error: {lastError}. Try again, or use "Type here instead."
            </p>
          )}
        </div>
      )}

      {!typeInstead ? (
        <div className="rn-card" style={{ marginTop: 18, padding: 22, display: 'flex', flexDirection: 'column', gap: 8, minHeight: 130 }}>
          <span className="rn-kicker">LIVE TRANSCRIPT</span>
          <p style={{ margin: 0, fontSize: 20, fontWeight: 500, fontFamily: 'Space Grotesk, sans-serif' }}>
            {transcript || '—'}
          </p>
        </div>
      ) : (
        <div className="rn-card" style={{ marginTop: 18, padding: 22, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <span className="rn-kicker">TYPE YOUR ENTRY</span>
          <textarea
            className="rn-input"
            rows={4}
            value={typedText}
            onChange={(e) => setTypedText(e.target.value)}
            placeholder={isRomanUrdu ? 'Masalan: seene mein dard hai...' : 'e.g. I have chest pain today...'}
          />
        </div>
      )}

      {submitError && <p style={{ color: 'var(--rn-red)', marginTop: 12 }}>{submitError}</p>}

      <div style={{ display: 'flex', gap: 12, marginTop: 22, flexWrap: 'wrap' }}>
        <button className="rn-btn rn-btn-primary" disabled={!canAnalyze} onClick={handleAnalyze}>
          {submitting ? 'Saving…' : 'Save & analyse this entry'}
        </button>
        <button className="rn-btn rn-btn-secondary" onClick={() => navigate('/check-in')}>
          Type instead — full check-in
        </button>
        {speechSupported && (
          <button className="rn-btn rn-btn-secondary" onClick={() => setTypeInstead((v) => !v)}>
            {typeInstead ? 'Use microphone' : 'Type here instead'}
          </button>
        )}
        <button className="rn-btn rn-btn-ghost" onClick={handleReset}>
          Start over
        </button>
      </div>

      {!speechSupported && (
        <p style={{ marginTop: 16, fontSize: 12, opacity: 0.75 }}>
          Your browser doesn't support voice recognition (Web Speech API) — try Chrome or Edge, or use the text field
          above, which submits the exact same way.
        </p>
      )}
      <p style={{ marginTop: 8, fontSize: 12, fontStyle: 'italic', opacity: 0.55 }}>
        Speech is converted to text by your browser where supported. If speech is unavailable, typing works exactly the
        same way.
      </p>
    </div>
  )
}

function MicGlyph({ listening }) {
  if (listening) {
    return (
      <svg width="46" height="46" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2">
        <rect x="6" y="6" width="12" height="12" rx="2" />
      </svg>
    )
  }
  return (
    <svg width="46" height="46" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 19v3" />
      <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
      <rect x="9" y="2" width="6" height="13" rx="3" />
    </svg>
  )
}
