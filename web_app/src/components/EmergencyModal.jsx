// Emergency contact sheet — content mirrors the "Emergency"/"Contact my
// doctor" bottom sheets in mobile_app's home_screen.dart and
// result_screen.dart (same emergency_contact_name/phone fields from
// PatientOut, same "call your local emergency number" disclaimer).
export function EmergencyModal({ profile, onClose }) {
  return (
    <div
      role="dialog"
      aria-modal="true"
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.4)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 50,
      }}
      onClick={onClose}
    >
      <div
        className="rn-card"
        style={{ maxWidth: 380, width: '90%', padding: 28 }}
        onClick={(e) => e.stopPropagation()}
      >
        <h3 style={{ fontSize: 20, marginBottom: 12 }}>Emergency contact</h3>
        <p style={{ margin: '0 0 4px' }}>{profile?.emergency_contact_name ?? 'Not set'}</p>
        <p style={{ margin: 0, fontSize: 22, fontWeight: 600 }}>{profile?.emergency_contact_phone ?? ''}</p>
        <p className="rn-muted" style={{ fontSize: 13, marginTop: 18 }}>
          If this is a medical emergency, call your local emergency number now.
        </p>
        <button className="rn-btn rn-btn-secondary rn-btn-block" style={{ marginTop: 16 }} onClick={onClose}>
          Close
        </button>
      </div>
    </div>
  )
}
