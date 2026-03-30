// src/contexts/AuthContext.jsx
//
// Firebase Auth context — production implementation
// ══════════════════════════════════════════════════
// Uses browserLocalPersistence so users stay logged in across page refreshes.
// onAuthStateChanged drives all auth state — no stale localStorage reads.
// Guards against premature redirects with isLoading state.

import React, { createContext, useContext, useState, useEffect } from 'react';
import {
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  signInWithPopup,
  GoogleAuthProvider,
  signOut,
  onAuthStateChanged,
  browserLocalPersistence,
  setPersistence,
  updateProfile,
  sendPasswordResetEmail,
} from 'firebase/auth';
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '../config/firebase';

const AuthContext = createContext(null);

const googleProvider = new GoogleAuthProvider();
googleProvider.setCustomParameters({ prompt: 'select_account' });

export const AuthProvider = ({ children }) => {
  const [currentUser, setCurrentUser]       = useState(null);
  const [guardianProfile, setGuardianProfile] = useState(null);
  const [loading, setLoading]               = useState(true);

  // ── Fetch or create guardian Firestore profile ────────────────────────────
  const fetchGuardianProfile = async (user) => {
    if (!user) { setGuardianProfile(null); return; }
    try {
      const ref  = doc(db, 'guardians', user.uid);
      const snap = await getDoc(ref);
      if (snap.exists()) {
        setGuardianProfile(snap.data());
      } else {
        // First-time: bootstrap a slim profile
        const profile = {
          uid:             user.uid,
          email:           user.email,
          displayName:     user.displayName || '',
          role:            'guardian',
          setup_complete:  false,
          linked_user_uid: null,
          fcm_tokens:      [],
          created_at:      serverTimestamp(),
        };
        await setDoc(ref, profile);
        setGuardianProfile(profile);
      }
    } catch (err) {
      console.error('Failed to fetch guardian profile:', err);
      setGuardianProfile(null);
    }
  };

  // ── Firebase Auth state listener — the single source of truth ────────────
  useEffect(() => {
    // Ensure local persistence before subscribing
    setPersistence(auth, browserLocalPersistence).catch(console.warn);

    const unsubscribe = onAuthStateChanged(auth, async (user) => {
      setCurrentUser(user);
      await fetchGuardianProfile(user);
      setLoading(false);
    });

    return unsubscribe; // cleanup on unmount
  }, []);

  // ── Auth actions ──────────────────────────────────────────────────────────

  const loginWithEmail = async (email, password) => {
    await setPersistence(auth, browserLocalPersistence);
    const result = await signInWithEmailAndPassword(auth, email, password);
    return result.user;
  };

  const loginWithGoogle = async () => {
    await setPersistence(auth, browserLocalPersistence);
    const result = await signInWithPopup(auth, googleProvider);
    return result.user;
  };

  const signup = async (email, password, displayName) => {
    await setPersistence(auth, browserLocalPersistence);
    const result = await createUserWithEmailAndPassword(auth, email, password);
    if (displayName) {
      await updateProfile(result.user, { displayName });
    }
    return result.user;
  };

  const logout = async () => {
    await signOut(auth);
    setGuardianProfile(null);
  };

  const resetPassword = async (email) => {
    await sendPasswordResetEmail(auth, email);
  };

  const updateGuardianProfile = async (updates) => {
    if (!currentUser) return;
    const ref = doc(db, 'guardians', currentUser.uid);
    await setDoc(ref, { ...updates, updated_at: serverTimestamp() }, { merge: true });
    setGuardianProfile(prev => ({ ...prev, ...updates }));
  };

  const value = {
    currentUser,
    guardianProfile,
    loading,
    loginWithEmail,
    loginWithGoogle,
    signup,
    logout,
    resetPassword,
    updateGuardianProfile,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
};

export default AuthContext;
