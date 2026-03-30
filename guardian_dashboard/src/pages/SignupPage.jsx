// src/pages/SignupPage.jsx — Full guardian signup with Firebase Auth
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Eye, EyeOff, User, Mail, Lock, AlertCircle, CheckCircle2 } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

/* ── Password strength indicator ──────────────────────────────── */
function PasswordStrength({ password }) {
  const checks = [
    { label: '8+ characters', ok: password.length >= 8 },
    { label: 'Uppercase letter', ok: /[A-Z]/.test(password) },
    { label: 'Number', ok: /\d/.test(password) },
  ];
  const score = checks.filter(c => c.ok).length;
  const color = score === 0 ? '#6B7280' : score === 1 ? '#EF4444' : score === 2 ? '#F59E0B' : '#10B981';
  const label = ['', 'Weak', 'Fair', 'Strong'][score];

  if (!password) return null;
  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ display: 'flex', gap: 4, marginBottom: 6 }}>
        {[0, 1, 2].map(i => (
          <div key={i} style={{
            flex: 1, height: 3, borderRadius: 2,
            background: i < score ? color : 'rgba(255,255,255,0.1)',
            transition: 'background 0.3s',
          }} />
        ))}
      </div>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        {checks.map(c => (
          <span key={c.label} style={{
            fontSize: 11, display: 'flex', alignItems: 'center', gap: 4,
            color: c.ok ? '#10B981' : 'rgba(255,255,255,0.4)',
          }}>
            {c.ok ? '✓' : '○'} {c.label}
          </span>
        ))}
      </div>
    </div>
  );
}

export default function SignupPage() {
  const navigate = useNavigate();
  const { signup } = useAuth();

  const [form, setForm] = useState({
    displayName: '',
    email:       '',
    password:    '',
    confirm:     '',
  });
  const [showPass,   setShowPass]   = useState(false);
  const [showConf,   setShowConf]   = useState(false);
  const [loading,    setLoading]    = useState(false);
  const [error,      setError]      = useState('');

  const update = (field) => (e) => setForm(prev => ({ ...prev, [field]: e.target.value }));

  const getErrorMessage = (code) => {
    const map = {
      'auth/email-already-in-use':    'An account already exists with this email.',
      'auth/invalid-email':           'Please enter a valid email address.',
      'auth/weak-password':           'Password must be at least 6 characters.',
      'auth/network-request-failed':  'Network error. Check your connection.',
      'auth/operation-not-allowed':   'Email sign-up is not enabled. Contact support.',
    };
    return map[code] || 'Sign up failed. Please try again.';
  };

  const handleSignup = async (e) => {
    e.preventDefault();
    setError('');

    if (!form.displayName.trim()) { setError('Please enter your name.'); return; }
    if (!form.email)               { setError('Please enter your email.'); return; }
    if (!form.password)            { setError('Please create a password.'); return; }
    if (form.password.length < 6)  { setError('Password must be at least 6 characters.'); return; }
    if (form.password !== form.confirm) { setError('Passwords do not match.'); return; }

    setLoading(true);
    try {
      await signup(form.email, form.password, form.displayName.trim());
      navigate('/setup/link');
    } catch (err) {
      setError(getErrorMessage(err.code));
      setLoading(false);
    }
  };

  return (
    <div className="auth-layout">

      {/* ── LEFT PANEL ─────────────────────────────────────────── */}
      <motion.div className="auth-left"
        initial={{ opacity: 0, x: -40 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: .55, ease: 'easeOut' }}
      >
        <div className="auth-logo">
          <div className="auth-logo-icon">👁</div>
          <div className="auth-logo-text">Drishti<span>Link</span></div>
        </div>

        <div className="auth-hero">
          <motion.h1 initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: .3 }}>
            Become a<br />Guardian
          </motion.h1>
          <motion.p initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .5 }}>
            Create your account to protect someone you love
          </motion.p>
        </div>

        <motion.div
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .7 }}
          style={{ marginTop: 'auto' }}
        >
          {[
            { icon: '📍', text: 'Track their location in real time' },
            { icon: '🔔', text: 'Get instant hazard alerts' },
            { icon: '🆘', text: 'Respond to SOS emergencies' },
            { icon: '🗺️', text: 'Define safe zones on the map' },
          ].map(f => (
            <div key={f.text} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              marginBottom: 14, color: 'rgba(255,255,255,0.8)', fontSize: 14,
            }}>
              <span style={{ fontSize: 20, width: 28 }}>{f.icon}</span>
              {f.text}
            </div>
          ))}
        </motion.div>
      </motion.div>

      {/* ── RIGHT PANEL ────────────────────────────────────────── */}
      <motion.div className="auth-right"
        initial={{ opacity: 0, x: 40 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: .55, ease: 'easeOut' }}
      >
        <div className="auth-form-wrap">
          <h2 className="auth-heading">Create Account</h2>
          <p className="auth-subheading">Join Drishti-Link as a guardian.</p>

          {error && (
            <motion.div
              initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }}
              style={{
                display: 'flex', alignItems: 'center', gap: 8,
                background: 'rgba(239,68,68,0.1)', border: '1px solid rgba(239,68,68,0.3)',
                borderRadius: 8, padding: '10px 14px', marginBottom: 16,
                fontSize: 13, color: '#EF4444',
              }}
            >
              <AlertCircle size={14} style={{ flexShrink: 0 }} />
              {error}
            </motion.div>
          )}

          <form onSubmit={handleSignup} style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>

            {/* Full Name */}
            <div className="form-group">
              <label className="form-label">Full Name</label>
              <div className="form-input-wrap">
                <User size={14} style={{
                  position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)',
                  color: 'var(--text-muted)', pointerEvents: 'none',
                }} />
                <input
                  id="signup-name"
                  type="text"
                  className="form-input"
                  placeholder="Priya Sharma"
                  value={form.displayName}
                  onChange={update('displayName')}
                  autoComplete="name"
                  style={{ paddingLeft: 36 }}
                />
              </div>
            </div>

            {/* Email */}
            <div className="form-group">
              <label className="form-label">Email Address</label>
              <div className="form-input-wrap">
                <Mail size={14} style={{
                  position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)',
                  color: 'var(--text-muted)', pointerEvents: 'none',
                }} />
                <input
                  id="signup-email"
                  type="email"
                  className="form-input"
                  placeholder="priya@example.com"
                  value={form.email}
                  onChange={update('email')}
                  autoComplete="email"
                  style={{ paddingLeft: 36 }}
                />
              </div>
            </div>

            {/* Password */}
            <div className="form-group">
              <label className="form-label">Password</label>
              <div className="form-input-wrap">
                <Lock size={14} style={{
                  position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)',
                  color: 'var(--text-muted)', pointerEvents: 'none',
                }} />
                <input
                  id="signup-password"
                  type={showPass ? 'text' : 'password'}
                  className="form-input"
                  placeholder="Create a strong password"
                  value={form.password}
                  onChange={update('password')}
                  autoComplete="new-password"
                  style={{ paddingLeft: 36, paddingRight: 42 }}
                />
                <span className="input-icon" onClick={() => setShowPass(!showPass)} style={{ cursor: 'pointer' }}>
                  {showPass ? <EyeOff size={15} /> : <Eye size={15} />}
                </span>
              </div>
              <PasswordStrength password={form.password} />
            </div>

            {/* Confirm Password */}
            <div className="form-group">
              <label className="form-label">Confirm Password</label>
              <div className="form-input-wrap">
                <Lock size={14} style={{
                  position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)',
                  color: 'var(--text-muted)', pointerEvents: 'none',
                }} />
                <input
                  id="signup-confirm"
                  type={showConf ? 'text' : 'password'}
                  className={`form-input ${form.confirm && form.password !== form.confirm ? 'input-error' : ''}`}
                  placeholder="Repeat password"
                  value={form.confirm}
                  onChange={update('confirm')}
                  autoComplete="new-password"
                  style={{ paddingLeft: 36, paddingRight: 42 }}
                />
                <span className="input-icon" onClick={() => setShowConf(!showConf)} style={{ cursor: 'pointer' }}>
                  {showConf ? <EyeOff size={15} /> : <Eye size={15} />}
                </span>
              </div>
              {form.confirm && form.password === form.confirm && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 6, fontSize: 12, color: '#10B981' }}>
                  <CheckCircle2 size={12} /> Passwords match
                </div>
              )}
            </div>

            {/* Terms */}
            <p style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 20, lineHeight: 1.6 }}>
              By creating an account you agree to our{' '}
              <span className="text-link" style={{ fontSize: 12 }}>Terms of Service</span> and{' '}
              <span className="text-link" style={{ fontSize: 12 }}>Privacy Policy</span>.
            </p>

            <button
              id="signup-submit"
              type="submit"
              className={`btn btn-primary ${loading ? 'btn-loading' : ''}`}
              disabled={loading}
            >
              {!loading && 'Create Guardian Account'}
            </button>
          </form>

          <div className="auth-footer" style={{ marginTop: 20 }}>
            Already a guardian?{' '}
            <span className="text-link" onClick={() => navigate('/login')}>Sign In</span>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
