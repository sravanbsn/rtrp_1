// src/pages/ForgotPasswordFlow.jsx — Password reset via Firebase
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Mail, ArrowLeft, CheckCircle, AlertCircle } from 'lucide-react'
import { useAuth } from '../contexts/AuthContext'

export default function ForgotPasswordFlow() {
  const navigate = useNavigate()
  const { resetPassword } = useAuth()

  const [email,   setEmail]   = useState('')
  const [sent,    setSent]    = useState(false)
  const [loading, setLoading] = useState(false)
  const [error,   setError]   = useState('')

  const handleReset = async (e) => {
    e.preventDefault()
    setError('')
    if (!email) { setError('Please enter your email address.'); return }
    setLoading(true)
    try {
      await resetPassword(email)
      setSent(true)
    } catch (err) {
      const map = {
        'auth/user-not-found':         'No account found with this email.',
        'auth/invalid-email':          'Please enter a valid email address.',
        'auth/network-request-failed': 'Network error. Check your connection.',
      }
      setError(map[err.code] || 'Failed to send reset email. Try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="auth-layout" style={{ justifyContent: 'center' }}>
      <motion.div
        initial={{ opacity: 0, y: 24 }} animate={{ opacity: 1, y: 0 }}
        style={{
          background: 'rgba(255,255,255,0.04)',
          border: '1px solid rgba(255,255,255,0.1)',
          borderRadius: 20,
          padding: '48px 40px',
          maxWidth: 440, width: '100%',
        }}
      >
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div style={{ fontSize: 40, marginBottom: 8 }}>🔐</div>
          <h2 style={{ fontSize: 22, fontWeight: 800, marginBottom: 8 }}>Reset Password</h2>
          <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 14 }}>
            Enter your guardian email and we will send a reset link.
          </p>
        </div>

        {sent ? (
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
            <div style={{ textAlign: 'center', padding: '24px 0' }}>
              <CheckCircle size={48} style={{ color: '#10B981', marginBottom: 16 }} />
              <h3 style={{ fontSize: 18, fontWeight: 700, marginBottom: 8 }}>Email Sent!</h3>
              <p style={{ color: 'rgba(255,255,255,0.6)', lineHeight: 1.7, marginBottom: 24 }}>
                We sent a password reset link to {email}. Check your inbox and spam folder.
              </p>
              <button className="btn btn-primary" onClick={() => navigate('/login')}>
                Back to Login
              </button>
            </div>
          </motion.div>
        ) : (
          <form onSubmit={handleReset}>
            {error && (
              <motion.div initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }}
                style={{
                  display: 'flex', alignItems: 'center', gap: 8,
                  background: 'rgba(239,68,68,0.1)', border: '1px solid rgba(239,68,68,0.3)',
                  borderRadius: 8, padding: '10px 14px', marginBottom: 16,
                  fontSize: 13, color: '#EF4444',
                }}>
                <AlertCircle size={14} /> {error}
              </motion.div>
            )}

            <div className="form-group">
              <label className="form-label">Email Address</label>
              <div className="form-input-wrap">
                <Mail size={14} style={{
                  position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)',
                  color: 'var(--text-muted)', pointerEvents: 'none',
                }} />
                <input
                  type="email"
                  className="form-input"
                  placeholder="guardian@example.com"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  autoFocus
                  style={{ paddingLeft: 36 }}
                />
              </div>
            </div>

            <button
              type="submit"
              className={`btn btn-primary ${loading ? 'btn-loading' : ''}`}
              disabled={loading}
              style={{ marginBottom: 16 }}
            >
              {!loading && 'Send Reset Link'}
            </button>

            <button
              type="button"
              className="btn btn-outline"
              onClick={() => navigate('/login')}
            >
              <ArrowLeft size={15} /> Back to Login
            </button>
          </form>
        )}
      </motion.div>
    </div>
  )
}
