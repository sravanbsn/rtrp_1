import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Eye, EyeOff } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

<<<<<<< HEAD
import { useAuth } from '../hooks/useAuth'

/* ── Floating particle background ─────────────────────────────── */
function Particles() {
  const particles = Array.from({ length: 14 }, (_, i) => ({
    id: i,
    size: 4 + Math.random() * 8,
    left: Math.random() * 100,
    delay: Math.random() * 8,
    duration: 6 + Math.random() * 8,
  }))
  return (
    <div style={{ position:'absolute', inset:0, overflow:'hidden', pointerEvents:'none' }}>
      {particles.map(p => (
        <div key={p.id} className="particle" style={{
          width: p.size, height: p.size,
          left: `${p.left}%`,
          animationDelay: `${p.delay}s`,
          animationDuration: `${p.duration}s`,
        }} />
      ))}
    </div>
  )
}
=======
// ... (Particles and HeroIllustration components remain the same)
>>>>>>> 3c44fd109675a7869954568aacbcf4cb55ac6532

export default function LoginPage() {
<<<<<<< HEAD
  const navigate = useNavigate()
  const { loginWithEmail, loginWithGoogle, isAuthenticated } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPass, setShowPass] = useState(false)
  const [remember, setRemember] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
=======
  const navigate = useNavigate();
  const { login } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPass, setShowPass] = useState(false);
  const [remember, setRemember] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
>>>>>>> 3c44fd109675a7869954568aacbcf4cb55ac6532

  useEffect(() => {
    if (isAuthenticated) {
      navigate('/dashboard', { replace: true })
    }
  }, [isAuthenticated, navigate])

  const handleLogin = async (e) => {
<<<<<<< HEAD
    e.preventDefault()
    setError('')
    if (!email || !password) { setError('Please fill in all fields.'); return }
    setLoading(true)
    try {
      await loginWithEmail(email, password)
      navigate('/dashboard')
    } catch (err) {
      setError(err.message || 'Failed to sign in')
      setLoading(false)
    }
  }

  const handleGoogleLogin = async () => {
    setError('')
    setLoading(true)
    try {
      await loginWithGoogle()
      navigate('/dashboard')
    } catch (err) {
      setError(err.message || 'Google sign in failed')
      setLoading(false)
    }
  }
=======
    e.preventDefault();
    setError('');
    if (!email || !password) {
      setError('Please fill in all fields.');
      return;
    }
    setLoading(true);
    // Simulate network call
    await new Promise((r) => setTimeout(r, 1400));
    // In a real app, you would verify credentials with a server
    const userData = { email }; // Simulate user data
    login(userData);
    setLoading(false);
    navigate('/dashboard');
  };
>>>>>>> 3c44fd109675a7869954568aacbcf4cb55ac6532

  // ... (JSX for the login page remains mostly the same)
    return (
    <div className="auth-layout">
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
          <motion.h1 initial={{ opacity:0, y:20 }} animate={{ opacity:1, y:0 }} transition={{ delay:.3 }}>
            Watch Over<br />Your World
          </motion.h1>
          <motion.p initial={{ opacity:0 }} animate={{ opacity:1 }} transition={{ delay:.5 }}>
            Stay connected to the ones you protect
          </motion.p>
        </div>
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
            <div style={{ background:'#FEF2F2', border:'1px solid #FCA5A5', borderRadius: 8,
              padding:'10px 14px', marginBottom:16, fontSize:13, color:'#DC2626' }}>
              {error}
            </div>
          )}

          <form onSubmit={handleLogin}>
            {/* Email */}
            <div className="form-group">
              <label className="form-label">Email</label>
              <div className="form-input-wrap">
                <input type="email" className={`form-input ${error ? 'input-error' : ''}`}
                  placeholder="guardian@example.com"
                  value={email} onChange={e => setEmail(e.target.value)}
                  style={{ paddingLeft: 14 }}
                />
              </div>
            </div>

            {/* Password */}
            <div className="form-group">
              <label className="form-label">Password</label>
              <div className="form-input-wrap">
                <input type={showPass ? 'text' : 'password'}
                  className={`form-input ${error ? 'input-error' : ''}`}
                  placeholder="••••••••"
                  value={password} onChange={e => setPassword(e.target.value)}
                  style={{ paddingRight: 42 }}
                />
                <span className="input-icon" onClick={() => setShowPass(!showPass)}>
                  {showPass ? <EyeOff size={16} /> : <Eye size={16} />}
                </span>
              </div>
            </div>

            {/* Remember + Forgot */}
            <div className="form-row-between">
              <label className="checkbox-row" style={{ margin: 0 }}>
                <input type="checkbox" checked={remember} onChange={e => setRemember(e.target.checked)} />
                <span style={{ fontSize:13, color:'var(--text-secondary)' }}>Remember me</span>
              </label>
              <span className="text-link" onClick={() => navigate('/forgot')}>Forgot Password?</span>
            </div>

            {/* Submit */}
            <button type="submit" className={`btn btn-primary ${loading ? 'btn-loading' : ''}`}
              disabled={loading}>
              {!loading && 'Sign In'}
            </button>
          </form>

          <div className="divider">or</div>

          {/* Google */}
          <button className="btn btn-outline" style={{ gap: 10 }}
            onClick={() => navigate('/dashboard')}>
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
  )
}