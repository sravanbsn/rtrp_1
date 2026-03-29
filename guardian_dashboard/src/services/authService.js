// src/services/authService.js
import { 
  signInWithEmailAndPassword, 
  createUserWithEmailAndPassword,
  signInWithPopup,
  GoogleAuthProvider,
  sendPasswordResetEmail,
  sendEmailVerification,
  setPersistence,
  browserLocalPersistence
} from 'firebase/auth';
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '../config/firebase';

const googleProvider = new GoogleAuthProvider();

export const signInWithEmailPassword = async (email, password) => {
  try {
    await setPersistence(auth, browserLocalPersistence);
    const userCredential = await signInWithEmailAndPassword(auth, email, password);
    const user = userCredential.user;

    // Check user role
    const userDocRef = doc(db, 'users', user.uid);
    const userDoc = await getDoc(userDocRef);

    if (!userDoc.exists() || userDoc.data()?.profile?.role !== 'guardian') {
      await auth.signOut();
      throw new Error("Guardian access only. Please use mobile app for regular users.");
    }

    const guardianDocRef = doc(db, 'guardians', user.uid);
    const guardianDoc = await getDoc(guardianDocRef);

    return {
      user,
      guardianProfile: guardianDoc.exists() ? guardianDoc.data() : null
    };
  } catch (error) {
    console.error("Login mapping error", error);
    throw error;
  }
};

export const signUpGuardian = async (email, password, name, phone) => {
  try {
    await setPersistence(auth, browserLocalPersistence);
    const userCredential = await createUserWithEmailAndPassword(auth, email, password);
    const user = userCredential.user;

    // 1. Create base profile (Role: guardian)
    const userRef = doc(db, 'users', user.uid);
    await setDoc(userRef, {
      profile: {
        name,
        phone,
        role: 'guardian',
        language: 'english',
        photo_url: user.photoURL || '',
        created_at: serverTimestamp(),
        last_active: serverTimestamp(),
        app_version: 'web-dashboard-1.0'
      }
    });

    // 2. Create Guardian specific data
    const guardianRef = doc(db, 'guardians', user.uid);
    await setDoc(guardianRef, {
      user_id: '', // Will be linked later
      name,
      phone,
      email,
      relation: 'unspecified',
      active: true,
      fcm_tokens: [],
      notification_prefs: {
        sos: true,
        override: true,
        session_updates: false,
        zone_alerts: true,
        battery_low: true,
        channels: {
          push: true,
          sms: false,
          whatsapp: false,
          email: true
        }
      },
      created_at: serverTimestamp()
    });

    // 3. Send email verification
    await sendEmailVerification(user);

    return user;
  } catch (error) {
    throw error;
  }
};

export const signInWithGoogle = async () => {
  try {
    await setPersistence(auth, browserLocalPersistence);
    const result = await signInWithPopup(auth, googleProvider);
    const user = result.user;

    const userDocRef = doc(db, 'users', user.uid);
    const userDoc = await getDoc(userDocRef);

    if (userDoc.exists()) {
      if (userDoc.data()?.profile?.role !== 'guardian') {
        await auth.signOut();
        throw new Error("Guardian access only. Please use mobile app for regular users.");
      }
    } else {
      // First time Google Sign in -> create guardian profile
      await setDoc(userDocRef, {
        profile: {
          name: user.displayName,
          phone: user.phoneNumber || '',
          role: 'guardian',
          language: 'english',
          photo_url: user.photoURL || '',
          created_at: serverTimestamp(),
          last_active: serverTimestamp()
        }
      });

      const guardianRef = doc(db, 'guardians', user.uid);
      await setDoc(guardianRef, {
        user_id: '',
        name: user.displayName,
        phone: user.phoneNumber || '',
        email: user.email,
        relation: 'unspecified',
        active: true,
        fcm_tokens: [],
        notification_prefs: {
          sos: true,
          override: true,
          session_updates: false,
          zone_alerts: true,
          battery_low: true,
          channels: { push: true, sms: false, whatsapp: false, email: true }
        },
        created_at: serverTimestamp()
      });
    }

    const guardianDocRef = doc(db, 'guardians', user.uid);
    const guardianDoc = await getDoc(guardianDocRef);

    return {
      user,
      guardianProfile: guardianDoc.exists() ? guardianDoc.data() : null
    };
  } catch (error) {
    throw error;
  }
};

export const sendPasswordReset = async (email) => {
  // Can be configured with custom action code settings for a branded reset page
  const actionCodeSettings = {
    url: 'https://drishti-link.web.app/login',
    handleCodeInApp: true
  };
  return sendPasswordResetEmail(auth, email, actionCodeSettings);
};

export const logout = () => {
  return auth.signOut();
};
