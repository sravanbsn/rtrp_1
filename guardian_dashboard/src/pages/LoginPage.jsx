// src/pages/LoginPage.jsx — Guardian Login with real Firebase Auth
import { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Eye, EyeOff, AlertCircle } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

/* ── Floating particle background ─────────────────────────────── */
function Particles() {
  const particles = Array.from({ length: 14 }, (_, i) => ({
    id: i,
    size: 4 + Math.random() * 8,
    left: Math.random() * 100,
    delay: Math.random() * 8,
    duration: 6 + Math.random() * 8,
  }));
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', pointerEvents: 'none' }}>
      {particles.map(p => (
        <div key={p.id} className="particle" style={{
          width: p.size, height: p.size,
          left: `${p.left}%`,
          animationDelay: `${p.delay}s`,
          animationDuration: `${p.duration}s`,
        }} />
      ))}
    </div>
  );
}

export default function LoginPage() {
  const navigate  = useNavigate();
  const location  = useLocation();
  const { loginWithEmail, loginWithGoogle, currentUser } = useAuth();

  const [email,    setEmail]    = useState('');
  const [password, setPassword] = useState('');
  const [showPass, setShowPass] = useState(false);
  const [loading,  setLoading]  = useState(false);
  const [error,    setError]    = useState('');

  const from = location.state?.from?.pathname || '/dashboard';

  // Already authenticated → go to dashboard
  useEffect(() => {
    if (currentUser) navigate('/dashboard', { replace: true });
  }, [currentUser, navigate]);

  const getErrorMessage = (code) => {
    const map = {
      'auth/user-not-found':      'No account found with this email.',
      'auth/wrong-password':      'Incorrect password. Please try again.',
      'auth/invalid-email':       'Please enter a valid email address.',
      'auth/too-many-requests':   'Too many attempts. Please try again later.',
      'auth/user-disabled':       'This account has been disabled.',
      'auth/network-request-failed': 'Network error. Check your connection.',
      'auth/invalid-credential':  'Invalid email or password.',
    };
    return map[code] || 'Sign in failed. Please try again.';
  };

  const handleLogin = async (e) => {
    e.preventDefault();
    setError('');
    if (!email || !password) { setError('Please fill in all fields.'); return; }
    setLoading(true);
    try {
      await loginWithEmail(email, password);
      navigate(from, { replace: true }); // goes to dashboard or intended page
    } catch (err) {
      setError(getErrorMessage(err.code));
      setLoading(false);
    }
  };

  const handleGoogleLogin = async () => {
    setError('');
    setLoading(true);
    try {
      await loginWithGoogle();
      navigate(from, { replace: true });
    } catch (err) {
      if (err.code !== 'auth/popup-closed-by-user') {
        setError(getErrorMessage(err.code));
      }
      setLoading(false);
    }
  };

  return (
    <div className="auth-layout">
      <Particles />

      {/* ── LEFT PANEL ─────────────────────────────────────────── */}
      <motion.div className="auth-left"
        initial={{ opacity: 0, x: -40 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: .55, ease: 'easeOut' }}
      >
        {/* Logo */}
        <div className="auth-logo">
          <div className="auth-logo-icon">👁</div>
          <div className="auth-logo-text">Drishti<span>Link</span></div>
        </div>

        {/* Hero */}
        <div className="auth-hero">
          <motion.h1 initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: .3 }}>
            Watch Over<br />Your World
          </motion.h1>
          <motion.p initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .5 }}>
            Stay connected to the ones you protect
          </motion.p>
        </div>

        {/* Feature tags */}
        <motion.div
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: .7 }}
          style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 'auto' }}
        >
          {['🛡️ Real-time alerts', '📍 Live location', '🆘 SOS monitoring'].map(tag => (
            <span key={tag} style={{
              background: 'rgba(232,135,26,0.15)',
              border: '1px solid rgba(232,135,26,0.3)',
              color: '#E8871A',
              fontSize: 12, fontWeight: 600,
              padding: '6px 12px', borderRadius: 20,
            }}>{tag}</span>
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
          <h2 className="auth-heading">Guardian Login</h2>
          <p className="auth-subheading">Welcome back. Let's make sure they're safe.</p>

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

          <form onSubmit={handleLogin}>
            {/* Email */}
            <div className="form-group">
              <label className="form-label">Email</label>
              <div className="form-input-wrap">
                <input
                  id="login-email"
                  type="email"
                  className={`form-input ${error ? 'input-error' : ''}`}
                  placeholder="guardian@example.com"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  autoComplete="email"
                  style={{ paddingLeft: 14 }}
                />
              </div>
            </div>

            {/* Password */}
            <div className="form-group">
              <label className="form-label">Password</label>
              <div className="form-input-wrap">
                <input
                  id="login-password"
                  type={showPass ? 'text' : 'password'}
                  className={`form-input ${error ? 'input-error' : ''}`}
                  placeholder="••••••••"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  autoComplete="current-password"
                  style={{ paddingRight: 42 }}
                />
                <span className="input-icon" onClick={() => setShowPass(!showPass)} style={{ cursor: 'pointer' }}>
                  {showPass ? <EyeOff size={16} /> : <Eye size={16} />}
                </span>
              </div>
            </div>

            {/* Remember + Forgot */}
            <div className="form-row-between">
              <span />
              <span className="text-link" onClick={() => navigate('/forgot')}>Forgot Password?</span>
            </div>

            {/* Submit */}
            <button
              id="login-submit"
              type="submit"
              className={`btn btn-primary ${loading ? 'btn-loading' : ''}`}
              disabled={loading}
            >
              {!loading && 'Sign In'}
            </button>
          </form>

          <div className="divider">or</div>

          {/* Google */}
          <button
            id="login-google"
            className="btn btn-outline"
            style={{ gap: 10 }}
            onClick={handleGoogleLogin}
            disabled={loading}
          >
            <svg width="18" height="18" viewBox="0 0 18 18">
              <path fill="#4285F4" d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844c-.209 1.125-.843 2.078-1.796 2.717v2.258h2.908c1.702-1.567 2.684-3.874 2.684-6.615z"/>
              <path fill="#34A853" d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 009 18z"/>
              <path fill="#FBBC05" d="M3.964 10.71A5.41 5.41 0 013.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.996 8.996 0 000 9c0 1.452.348 2.827.957 4.042l3.007-2.332z"/>
              <path fill="#EA4335" d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 00.957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z"/>
            </svg>
            Continue with Google
          </button>

          <div className="auth-footer">
            New guardian? <span className="text-link" onClick={() => navigate('/signup')}>Sign Up</span>
          </div>
        </div>
      </motion.div>
    </div>
  );
}