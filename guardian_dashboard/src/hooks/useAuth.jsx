// src/hooks/useAuth.jsx
import React, { createContext, useContext, useState, useEffect } from 'react';
import { onAuthStateChanged } from 'firebase/auth';
import { doc, onSnapshot } from 'firebase/firestore';
import { auth, db } from '../config/firebase';
import {
  signInWithEmailPassword,
  signInWithGoogle,
  sendPasswordReset,
  logout,
  signUpGuardian,
} from '../services/authService';

const AuthContext = createContext(null);

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
};

export const AuthProvider = ({ children }) => {
  const [currentUser, setCurrentUser]       = useState(null);
  const [guardianProfile, setGuardianProfile] = useState(null);
  // initializing = true until Firebase has resolved the persisted session
  const [initializing, setInitializing]     = useState(true);
  const [error, setError]                   = useState(null);

  useEffect(() => {
    let unsubProfile = () => {};

    const unsubAuth = onAuthStateChanged(auth, (user) => {
      // Cancel any previous profile listener
      unsubProfile();

      if (user) {
        setCurrentUser(user);

        // Watch the guardian document in Firestore
        const ref = doc(db, 'guardians', user.uid);
        unsubProfile = onSnapshot(
          ref,
          (snap) => {
            setGuardianProfile(snap.exists() ? snap.data() : null);
            // Firebase session is resolved – hide the splash
            setInitializing(false);
          },
          (err) => {
            console.error('Guardian profile listen error:', err);
            setError('Could not load guardian profile.');
            setInitializing(false);
          }
        );
      } else {
        setCurrentUser(null);
        setGuardianProfile(null);
        setInitializing(false);
      }
    });

    return () => {
      unsubAuth();
      unsubProfile();
    };
  }, []);

  /* ── Auth actions ──────────────────────────────────────────── */
  const loginWithEmail = async (email, password) => {
    setError(null);
    try {
      await signInWithEmailPassword(email, password);
    } catch (err) {
      setError(err.message);
      throw err;
    }
  };

  const loginWithGoogle = async () => {
    setError(null);
    try {
      await signInWithGoogle();
    } catch (err) {
      setError(err.message);
      throw err;
    }
  };

  const registerGuardian = async (email, password, name, phone) => {
    setError(null);
    try {
      await signUpGuardian(email, password, name, phone);
    } catch (err) {
      setError(err.message);
      throw err;
    }
  };

  const resetPassword = async (email) => {
    setError(null);
    try {
      await sendPasswordReset(email);
    } catch (err) {
      setError(err.message);
      throw err;
    }
  };

  const signOut = async () => {
    setError(null);
    try {
      await logout();
      setCurrentUser(null);
      setGuardianProfile(null);
    } catch (err) {
      console.error(err);
    }
  };

  /* ── Context value ─────────────────────────────────────────── */
  const value = {
    currentUser,
    guardianProfile,
    // expose initializing separately so components can show a splash
    loading: initializing,
    error,
    isAuthenticated: !!currentUser,
    // A user who is authenticated but has no profile yet is still "valid"
    // (they are mid-onboarding). isGuardian means profile is fully set up.
    isGuardian: !!currentUser && !!guardianProfile,
    loginWithEmail,
    loginWithGoogle,
    registerGuardian,
    resetPassword,
    logout: signOut,
  };

  /* Show a minimal full-screen splash while Firebase resolves */
  if (initializing) {
    return (
      <div style={{
        display: 'flex', height: '100vh', width: '100vw',
        alignItems: 'center', justifyContent: 'center',
        background: '#0f172a', fontFamily: 'system-ui, sans-serif',
      }}>
        <div style={{ textAlign: 'center', color: '#94a3b8' }}>
          <div style={{ fontSize: 36, marginBottom: 12 }}>👁️</div>
          <div style={{ fontSize: 15, fontWeight: 500 }}>Loading DrishtiLink…</div>
        </div>
      </div>
    );
  }

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};
