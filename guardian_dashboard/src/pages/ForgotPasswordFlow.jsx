import { useState, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import { ArrowLeft, Mail, Check } from 'lucide-react'

function Particles() {
  const particles = Array.from({ length: 14 }, (_, i) => ({
    id: i, size: 4 + Math.random() * 8,
    left: Math.random() * 100,
    delay: Math.random() * 8,
    duration: 6 + Math.random() * 8,
  }))
  return (
    <div style={{ position:'absolute', inset:0, overflow:'hidden', pointerEvents:'none' }}>
      {particles.map(p => (
        <div key={p.id} className="particle" style={{
          width: p.size, height: p.size, left: `${p.left}%`,
          animationDelay: `${p.delay}s`, animationDuration: `${p.duration}s`,
        }} />
      ))}
    </div>
  )
}

const steps = ['Email', 'Verify OTP', 'New Password']

/* ── OTP input component ───────────────────────────────────────── */
function OTPInput({ onComplete }) {
  const [otp, setOtp] = useState(['','','','','',''])
  const refs = Array.from({ length: 6 }, () => useRef())

  const handleChange = (i, val) => {
    if (!/^\d*$/.test(val)) return
    const next = [...otp]; next[i] = val.slice(-1)
    setOtp(next)
    if (val && i < 5) refs[i+1].current.focus()
    if (next.every(v => v)) onComplete(next.join(''))
  }
  const handleKey = (i, e) => {
    if (e.key === 'Backspace' && !otp[i] && i > 0) refs[i-1].current.focus()
  }

  return (
    <div className="otp-row">
      {otp.map((v, i) => (
        <input key={i} ref={refs[i]} className="otp-input"
          type="text" inputMode="numeric" maxLength={1}
          value={v}
          onChange={e => handleChange(i, e.target.value)}
          onKeyDown={e => handleKey(i, e)}
          style={{ background: v ? '#FFFBF5' : 'white', borderColor: v ? 'var(--saffron)' : undefined }}
        />
      ))}
    </div>
  )
}

/* ── Forgot Password Flow ──────────────────────────────────────── */
export default function ForgotPasswordFlow() {
  const navigate = useNavigate()
  const [step, setStep] = useState(0) // 0=email, 1=otp, 2=reset
  const [email, setEmail] = useState('')
  const [otpVerified, setOtpVerified] = useState(false)
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [loading, setLoading] = useState(false)
  const [done, setDone] = useState(false)

  const handleEmail = async (e) => {
    e.preventDefault()
    if (!email) return
    setLoading(true)
    await new Promise(r => setTimeout(r, 1200))
    setLoading(false)
    setStep(1)
  }

  const handleOTP = async (code) => {
    await new Promise(r => setTimeout(r, 600))
    setOtpVerified(true)
    setTimeout(() => setStep(2), 900)
  }

  const handleReset = async (e) => {
    e.preventDefault()
    if (!password || password !== confirm) return
    setLoading(true)
    await new Promise(r => setTimeout(r, 1200))
    setLoading(false)
    setDone(true)
    setTimeout(() => navigate('/login'), 2000)
  }

  return (
    <div className="auth-layout">
      {/* Left panel */}
      <div className="auth-left" style={{ justifyContent:'center', alignItems:'center' }}>
        <Particles />
        <div style={{ position:'relative', zIndex:1, textAlign:'center' }}>
          <div className="auth-logo" style={{ justifyContent:'center', marginBottom: 32 }}>
            <div className="auth-logo-icon">👁</div>
            <div className="auth-logo-text">Drishti<span>Link</span></div>
          </div>
          <div style={{ fontSize: 64, marginBottom: 20 }}>
            {step === 0 ? '📧' : step === 1 ? '🔐' : '🔑'}
          </div>
          <h2 style={{ color:'white', fontSize: 24, fontWeight:800, marginBottom: 8 }}>
            {steps[step]}
          </h2>
          <p style={{ color:'var(--text-muted)', fontSize:14 }}>
            {step === 0 && "Enter your email to receive a reset code"}
            {step === 1 && "Check your inbox for the 6-digit code"}
            {step === 2 && "Choose a strong new password"}
          </p>
          {/* Step dots */}
          <div style={{ display:'flex', justifyContent:'center', gap:8, marginTop:32 }}>
            {steps.map((_, i) => (
              <div key={i} style={{
                width: 8, height: 8, borderRadius:'50%',
                background: i <= step ? 'var(--saffron)' : 'rgba(255,255,255,.2)',
                transition:'all .3s',
              }} />
            ))}
          </div>
        </div>
      </div>

      {/* Right panel */}
      <div className="auth-right">
        <div className="auth-form-wrap">
          <button className="btn btn-ghost" style={{ marginBottom:24, justifyContent:'flex-start', padding:0 }}
            onClick={() => step === 0 ? navigate('/login') : setStep(step-1)}>
            <ArrowLeft size={16} /> Back
          </button>

          <AnimatePresence mode="wait">
            {/* ── Step 0: Email ─────────────────────────────── */}
            {step === 0 && (
              <motion.div key="email"
                initial={{ opacity:0, x:30 }} animate={{ opacity:1, x:0 }} exit={{ opacity:0, x:-30 }}>
                <h2 className="auth-heading">Forgot Password?</h2>
                <p className="auth-subheading">We'll send you a verification code.</p>
                <form onSubmit={handleEmail}>
                  <div className="form-group">
                    <label className="form-label">Email Address</label>
                    <input type="email" className="form-input" placeholder="guardian@example.com"
                      value={email} onChange={e => setEmail(e.target.value)} />
                  </div>
                  <button type="submit" className={`btn btn-primary ${loading ? 'btn-loading' : ''}`}
                    disabled={loading}>
                    {!loading && 'Send Code'}
                  </button>
                </form>
              </motion.div>
            )}

            {/* ── Step 1: OTP ────────────────────────────────── */}
            {step === 1 && (
              <motion.div key="otp"
                initial={{ opacity:0, x:30 }} animate={{ opacity:1, x:0 }} exit={{ opacity:0, x:-30 }}>
                <h2 className="auth-heading">Enter Code</h2>
                <p className="auth-subheading">Sent to <strong>{email}</strong></p>
                {!otpVerified ? (
                  <>
                    <OTPInput onComplete={handleOTP} />
                    <p className="text-center text-sm text-muted">
                      Didn't receive it? <span className="text-link">Resend</span>
                    </p>
                  </>
                ) : (
                  <motion.div initial={{ scale:.8, opacity:0 }} animate={{ scale:1, opacity:1 }}
                    style={{ textAlign:'center', padding:'32px 0' }}>
                    <div style={{
                      width:64, height:64, borderRadius:'50%',
                      background:'var(--success)', display:'flex',
                      alignItems:'center', justifyContent:'center',
                      margin:'0 auto 16px',
                    }}>
                      <Check size={32} color="white" />
                    </div>
                    <p className="fw-700">Code verified! Redirecting…</p>
                  </motion.div>
                )}
              </motion.div>
            )}

            {/* ── Step 2: New Password ───────────────────────── */}
            {step === 2 && (
              <motion.div key="reset"
                initial={{ opacity:0, x:30 }} animate={{ opacity:1, x:0 }} exit={{ opacity:0, x:-30 }}>
                <h2 className="auth-heading">New Password</h2>
                <p className="auth-subheading">Choose something strong and memorable.</p>
                {!done ? (
                  <form onSubmit={handleReset}>
                    <div className="form-group">
                      <label className="form-label">New Password</label>
                      <input type="password" className="form-input"
                        placeholder="Min. 8 characters"
                        value={password} onChange={e => setPassword(e.target.value)} />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Confirm Password</label>
                      <input type="password"
                        className={`form-input ${confirm && confirm !== password ? 'input-error' : ''}`}
                        placeholder="Repeat password"
                        value={confirm} onChange={e => setConfirm(e.target.value)} />
                      {confirm && confirm !== password && (
                        <p style={{ color:'var(--danger)', fontSize:12, marginTop:4 }}>Passwords don't match.</p>
                      )}
                    </div>
                    {/* Strength meter */}
                    <div style={{ marginBottom: 20 }}>
                      {[0,1,2,3].map(i => (
                        <span key={i} style={{
                          display:'inline-block', height:4, width:'23%',
                          borderRadius:4, marginRight:'1%',
                          background: password.length > (i+1)*3 ? 'var(--saffron)' : '#E8EDF5',
                          transition:'all .3s',
                        }} />
                      ))}
                    </div>
                    <button type="submit" className={`btn btn-primary ${loading ? 'btn-loading' : ''}`}
                      disabled={loading || !password || password !== confirm}>
                      {!loading && 'Reset Password'}
                    </button>
                  </form>
                ) : (
                  <motion.div initial={{ scale:.8,opacity:0 }} animate={{ scale:1,opacity:1 }}
                    style={{ textAlign:'center', padding:'32px 0' }}>
                    <div style={{
                      width:64, height:64, borderRadius:'50%', background:'var(--saffron)',
                      display:'flex', alignItems:'center', justifyContent:'center', margin:'0 auto 16px',
                    }}>
                      <Check size={32} color="white" />
                    </div>
                    <p className="fw-700">Password reset! Taking you to login…</p>
                  </motion.div>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  )
}
