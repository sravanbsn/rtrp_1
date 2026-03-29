import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { CheckCircle, Search, User } from 'lucide-react'

/* ── Shared Onboarding Header ────────────────────────────────── */
export function OnboardingHeader({ step }) {
  const labels = ['Link User', 'Alert Preferences', 'Safe Zones']
  return (
    <div className="onboarding-header">
      <div className="onboarding-logo">
        <div className="onboarding-logo-icon">👁</div>
        <div className="onboarding-logo-text">Drishti<span>Link</span></div>
      </div>
      <div className="progress-wrap">
        <div className="progress-steps">
          {labels.map((label, i) => (
            <div key={i} style={{ display:'flex', alignItems:'center' }}>
              <div className={`step-dot ${i < step ? 'done' : i === step ? 'active' : 'pending'}`}>
                {i < step ? '✓' : i + 1}
              </div>
              {i < labels.length - 1 && (
                <div className={`step-line ${i < step ? 'done' : ''}`} />
              )}
            </div>
          ))}
        </div>
        <div className="progress-label">Step {step + 1} of {labels.length} — {labels[step]}</div>
      </div>
      <div style={{ width: 180 }} />
    </div>
  )
}

/* ── Step 1: Link User ─────────────────────────────────────────── */
export default function OnboardingStep1() {
  const navigate = useNavigate()
  const [phone, setPhone] = useState('')
  const [loading, setLoading] = useState(false)
  const [linked, setLinked] = useState(false)

  const handleLink = async (e) => {
    e.preventDefault()
    if (!phone) return
    setLoading(true)
    await new Promise(r => setTimeout(r, 1600))
    setLoading(false)
    setLinked(true)
  }

  return (
    <div className="onboarding-root">
      <OnboardingHeader step={0} />
      <div className="onboarding-body">
        <motion.div className="onboarding-card"
          initial={{ opacity:0, y:24 }} animate={{ opacity:1, y:0 }}
          transition={{ duration:.4, ease:'easeOut' }}>

          <h2 className="onboarding-heading">Who are you watching over?</h2>
          <p className="onboarding-sub">
            Enter their phone number to send a link request.
            We'll send a confirmation to their phone.
          </p>

          {!linked ? (
            <form onSubmit={handleLink}>
              <div className="form-group">
                <label className="form-label">Phone Number</label>
                <div style={{ display:'flex', gap:10 }}>
                  {/* Country prefix */}
                  <select style={{
                    height:46, padding:'0 10px', borderRadius:'var(--radius-md)',
                    border:'1.5px solid #DDE3EE', background:'var(--off-white)',
                    fontSize:14, color:'var(--text-primary)', outline:'none', cursor:'pointer',
                  }}>
                    <option>🇮🇳 +91</option>
                    <option>🇺🇸 +1</option>
                    <option>🇬🇧 +44</option>
                  </select>
                  <input type="tel" className="form-input"
                    placeholder="98765 43210"
                    value={phone} onChange={e => setPhone(e.target.value)}
                    style={{ flex:1 }}
                  />
                </div>
              </div>

              {/* Info box */}
              <div style={{
                display:'flex', gap:12, padding:'14px 16px',
                background:'#EFF6FF', border:'1px solid #BFDBFE',
                borderRadius:'var(--radius-md)', marginBottom:20, fontSize:13,
                color:'var(--info)', lineHeight:1.5,
              }}>
                <span>ℹ️</span>
                <span>
                  A confirmation request will be sent to their Drishti-Link app.
                  They must approve the link for you to become their guardian.
                </span>
              </div>

              <button type="submit"
                className={`btn btn-primary ${loading ? 'btn-loading' : ''}`}
                disabled={loading}>
                {!loading && '📨 Send Link Request'}
              </button>
            </form>
          ) : (
            // Linked user card
            <motion.div
              initial={{ opacity:0, scale:.95 }} animate={{ opacity:1, scale:1 }}
              transition={{ duration:.4, type:'spring' }}>
              <div style={{
                display:'flex', alignItems:'center', gap:12,
                padding:'12px 16px', background:'#F0FDF4',
                borderRadius:'var(--radius-md)', border:'1px solid #A7F3D0',
                marginBottom: 20, fontSize:13, color:'var(--success)',
              }}>
                <CheckCircle size={16} />
                Link request sent! Waiting for their confirmation…
              </div>

              <div className="user-link-card">
                <div className="user-link-avatar">AR</div>
                <div className="user-link-info">
                  <div className="user-link-name">Arjun Sharma</div>
                  <div className="user-link-sub">+91 {phone} • Drishti-Link user</div>
                  <div style={{ display:'flex', alignItems:'center', gap:6, marginTop:4,
                    fontSize:12, color:'var(--success)', fontWeight:600 }}>
                    <div style={{ width:6, height:6, borderRadius:'50%', background:'var(--success)' }} />
                    Active
                  </div>
                </div>
                <div className="badge-linked">
                  <CheckCircle size={13} /> Linked ✓
                </div>
              </div>

              <button className="btn btn-primary mt-lg"
                onClick={() => navigate('/setup/alerts')}>
                Continue to Alert Preferences →
              </button>
            </motion.div>
          )}
        </motion.div>
      </div>
    </div>
  )
}
