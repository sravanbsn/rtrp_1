// src/components/SignUpPage.jsx
import React, { useState, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';

const SignUpPage = () => {
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [acceptTerms, setAcceptTerms] = useState(false);
  
  const [authError, setAuthError] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isSuccess, setIsSuccess] = useState(false);
  
  const { registerGuardian, loginWithGoogle, isAuthenticated } = useAuth();
  const navigate = useNavigate();

  // If user is ALREADY logged in when they visit this page → send to dashboard
  useEffect(() => {
    if (isAuthenticated && !isLoading) {
      navigate('/dashboard', { replace: true });
    }
  }, []); // run once on mount only – avoids race with newly created account

  const handleRegister = async (e) => {
    e.preventDefault();
    if (!acceptTerms) {
       setAuthError("You must accept the Terms & Conditions");
       return;
    }
    
    setAuthError('');
    setIsLoading(true);
    
    try {
      await registerGuardian(email, password, name, phone);
      setIsSuccess(true);
      // Navigate immediately – no delay needed
      navigate('/setup/link', { replace: true });
    } catch (err) {
      setAuthError(err.message || "Failed to create account.");
      setIsLoading(false);
    }
  };

  const handleGoogleSignup = async () => {
    if (!acceptTerms) {
       setAuthError("You must accept the Terms & Conditions first");
       return;
    }
    setAuthError('');
    setIsLoading(true);
    try {
      await loginWithGoogle();
      navigate('/setup/link', { replace: true });
    } catch (err) {
      setAuthError(err.message || "Google sign up failed.");
      setIsLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen bg-slate-50 items-center justify-center p-4">
      <div className="w-full max-w-lg bg-white p-8 md:p-12 rounded-2xl shadow-xl border border-slate-100">
        
        <div className="flex items-center gap-3 mb-8">
            <div className="h-8 w-8 bg-indigo-500 rounded-lg shadow-sm flex items-center justify-center font-bold text-white text-sm">D</div>
            <h1 className="text-xl font-bold tracking-tight text-slate-900">Drishti-Link</h1>
        </div>

        <h2 className="text-3xl font-bold text-slate-900 mb-2">Create Guardian Account</h2>
        <p className="text-slate-500 mb-8">Set up your profile to monitor your family member.</p>

        {isSuccess ? (
          <div className="bg-emerald-50 border border-emerald-200 text-emerald-700 p-6 rounded-xl flex flex-col items-center text-center">
            <div className="h-12 w-12 bg-emerald-100 rounded-full flex items-center justify-center mb-4">
               <svg className="w-6 h-6 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 13l4 4L19 7"></path></svg>
            </div>
            <h3 className="text-lg font-bold mb-2">Account Created</h3>
            <p>Verification email sent. Redirecting to dashboard...</p>
          </div>
        ) : (
          <form onSubmit={handleRegister} className="space-y-4">
            
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-slate-700 mb-1">Full Name</label>
                  <input type="text" required value={name} onChange={(e) => setName(e.target.value)}
                    className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-indigo-600 outline-none"
                    placeholder="Arjun's Guardian"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-700 mb-1">Phone (+91)</label>
                  <input type="tel" required value={phone} onChange={(e) => setPhone(e.target.value)}
                    className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-indigo-600 outline-none"
                    placeholder="9988776655"
                  />
                </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Email Address</label>
              <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)}
                className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-indigo-600 outline-none"
                placeholder="you@example.com"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Secure Password</label>
              <input type="password" required value={password} onChange={(e) => setPassword(e.target.value)}
                className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-indigo-600 outline-none"
                placeholder="Minimum 8 characters"
                minLength={8}
              />
               {/* Quick strength indicator UI */}
              {password.length > 0 && (
                  <div className="flex gap-1 mt-2">
                     <div className={`h-1 flex-1 rounded-full ${password.length > 3 ? 'bg-orange-400' : 'bg-slate-200'}`}></div>
                     <div className={`h-1 flex-1 rounded-full ${password.length > 6 ? 'bg-yellow-400' : 'bg-slate-200'}`}></div>
                     <div className={`h-1 flex-1 rounded-full ${password.length > 8 ? 'bg-emerald-500' : 'bg-slate-200'}`}></div>
                  </div>
              )}
            </div>

            <label className="flex items-start gap-3 mt-4 mb-6 pt-2">
              <input type="checkbox" checked={acceptTerms} onChange={(e)=>setAcceptTerms(e.target.checked)} className="mt-1 w-4 h-4 text-indigo-600 rounded" />
              <span className="text-sm text-slate-600">I agree to the Guardian Terms of Service and Privacy Policy. I promise to use this platform responsibly.</span>
            </label>

            {authError && (
              <div className="p-3 bg-red-50 text-red-600 text-sm rounded-lg border border-red-100">
                {authError}
              </div>
            )}

            <button type="submit" disabled={isLoading}
              className="w-full bg-[#f97316] hover:bg-[#ea580c] text-white font-medium py-3 rounded-lg shadow-md transition-all disabled:opacity-70 flex justify-center items-center h-12"
            >
              {isLoading ? <div className="h-5 w-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div> : "Create Account"}
            </button>
            
            <button type="button" onClick={handleGoogleSignup} disabled={isLoading}
                className="w-full bg-slate-50 border border-slate-300 text-slate-700 font-medium py-3 rounded-lg hover:bg-slate-100 transition-colors flex items-center justify-center gap-3"
            >
              Google
            </button>

          </form>
        )}

        <p className="mt-8 text-center text-slate-600">
          Already a guardian? <Link to="/login" className="text-indigo-600 font-semibold hover:underline">Log In</Link>
        </p>

      </div>
    </div>
  );
};

export default SignUpPage;
