import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BilingualText } from '../../components/BilingualText'
import { ApiException } from '../../core/apiClient'
import { usePatientData } from '../../state/PatientDataContext'

const WORDS = ['Very low', 'Low', 'Usual', 'Good', 'Very good']

// Quick Check-in — POST /entries with entry_type=quick + the 1-5 slider
// values + medicine_status + symptom checklist. Mirrors
// mobile_app/lib/screens/patient/quick_checkin_screen.dart, INCLUDING its
// deliberate deviation from the prototype mockup: sleep is an hours field
// (0-24), not a sixth 1-5 slider — the prototype mockup draws Sleep as one
// of five identical sliders, but entries.sleep_value is hours (confirmed
// backend scale — see context/decisions-log.md, 2026-08-24). Energy/Mood/
// Appetite/Mobility stay 1-5 sliders, matching both the prototype and
// app/schemas/entry.py's confirmed bounds.
export function QuickCheckinScreen() {
  const navigate = useNavigate()
  const { submitEntry, symptomChecklist } = usePatientData()

  const [sleep, setSleep] = useState(7)
  const [energy, setEnergy] = useState(3)
  const [mood, setMood] = useState(3)
  const [appetite, setAppetite] = useState(3)
  const [mobility, setMobility] = useState(3)
  const [weight, setWeight] = useState('')
  const [medicine, setMedicine] = useState('taken')
  const [selectedSymptoms, setSelectedSymptoms] = useState(new Set())
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(null)

  function toggleSymptom(id) {
    setSelectedSymptoms((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function handleSubmit() {
    setSubmitting(true)
    setError(null)
    try {
      const entry = await submitEntry({
        entryType: 'quick',
        sleepValue: sleep,
        energyValue: energy,
        moodValue: mood,
        appetiteValue: appetite,
        mobilityValue: mobility,
        weightValue: weight === '' ? null : Number(weight),
        medicineStatus: medicine,
        symptomIds: [...selectedSymptoms],
      })
      navigate('/result', { state: { entry }, replace: true })
    } catch (e) {
      setError(e instanceof ApiException ? e.message : 'Something went wrong. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div style={{ padding: '32px 40px', maxWidth: 820 }}>
      <BilingualText as="h1" en="Today's quick check-in" ur="Aaj ka roz-marra" style={{ fontSize: 28 }} />
      <p className="rn-muted" style={{ marginTop: 6, marginBottom: 22 }}>
        Nothing here is a test — move each line to whatever feels true today.
      </p>

      <div className="rn-card" style={{ padding: 26, display: 'flex', flexDirection: 'column', gap: 22 }}>
        <HoursSlider label="Sleep last night" value={sleep} onChange={setSleep} />
        <hr className="rn-hr" />
        <FiveSlider label="Energy" low="Very low" high="Very good" value={energy} onChange={setEnergy} />
        <FiveSlider label="Mood" low="Very low" high="Very good" value={mood} onChange={setMood} />
        <FiveSlider label="Appetite" low="Very poor" high="Very good" value={appetite} onChange={setAppetite} />
        <FiveSlider label="Mobility" low="Very limited" high="Very good" value={mobility} onChange={setMobility} />
        <hr className="rn-hr" />

        <label style={{ display: 'flex', flexDirection: 'column', gap: 6, maxWidth: 260 }}>
          <span style={{ fontSize: 14 }}>Weight today (kg) — optional</span>
          <input
            className="rn-input"
            type="number"
            step="0.1"
            value={weight}
            onChange={(e) => setWeight(e.target.value)}
          />
        </label>

        <hr className="rn-hr" />

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 20, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 16, fontWeight: 600 }}>Medicine today</span>
          <div style={{ display: 'flex', border: '1px solid var(--rn-divider)', borderRadius: 10, overflow: 'hidden' }}>
            {['taken', 'missed'].map((opt) => (
              <button
                key={opt}
                onClick={() => setMedicine(opt)}
                className="rn-btn"
                style={{
                  borderRadius: 0,
                  padding: '10px 20px',
                  fontSize: 14,
                  background: medicine === opt ? 'var(--rn-accent-200)' : 'transparent',
                  color: medicine === opt ? 'var(--rn-accent-dark)' : 'var(--rn-text)',
                  border: 'none',
                }}
              >
                {opt === 'taken' ? 'Taken' : 'Missed'}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="rn-card" style={{ marginTop: 16, padding: 22, display: 'flex', flexDirection: 'column', gap: 12 }}>
        <span className="rn-kicker">ANYTHING TODAY?</span>
        {symptomChecklist.length === 0 ? (
          <p className="rn-muted" style={{ fontSize: 13, margin: 0 }}>
            No specific checklist for your diagnosis — describe anything unusual in a Voice Diary entry instead.
          </p>
        ) : (
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {symptomChecklist.map((s) => (
              <button
                key={s.id}
                className={`rn-chip ${selectedSymptoms.has(s.id) ? 'rn-chip-selected' : ''}`}
                onClick={() => toggleSymptom(s.id)}
              >
                {s.symptom_name}
              </button>
            ))}
          </div>
        )}
      </div>

      {error && <p style={{ color: 'var(--rn-red)', marginTop: 14 }}>{error}</p>}

      <button className="rn-btn rn-btn-primary rn-btn-block" style={{ marginTop: 20 }} disabled={submitting} onClick={handleSubmit}>
        {submitting ? 'Saving…' : "Save today's check-in"}
      </button>
    </div>
  )
}

function FiveSlider({ label, low, high, value, onChange }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
        <span style={{ fontSize: 16, fontWeight: 600 }}>{label}</span>
        <span style={{ color: 'var(--rn-accent-dark)' }}>{WORDS[value - 1]}</span>
      </div>
      <input type="range" min={1} max={5} step={1} value={value} onChange={(e) => onChange(Number(e.target.value))} />
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, opacity: 0.5 }}>
        <span>{low}</span>
        <span>{high}</span>
      </div>
    </div>
  )
}

function HoursSlider({ label, value, onChange }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
        <span style={{ fontSize: 16, fontWeight: 600 }}>{label}</span>
        <span style={{ color: 'var(--rn-accent-dark)' }}>{value.toFixed(1)}h</span>
      </div>
      <input type="range" min={0} max={14} step={0.5} value={value} onChange={(e) => onChange(Number(e.target.value))} />
    </div>
  )
}
