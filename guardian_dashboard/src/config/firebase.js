// src/config/firebase.js
import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getDatabase } from 'firebase/database';
import { getMessaging, isSupported } from 'firebase/messaging';

// All config values come from environment variables.
// For local dev: create guardian_dashboard/.env with VITE_FIREBASE_* keys.
// For production: set these in Vercel / Netlify / Firebase Hosting env settings.
const firebaseConfig = {
  apiKey:            import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain:        import.meta.env.VITE_FIREBASE_AUTH_DOMAIN        || 'drishti-link.firebaseapp.com',
  databaseURL:       import.meta.env.VITE_FIREBASE_DATABASE_URL       || 'https://drishti-link-default-rtdb.asia-southeast1.firebasedatabase.app',
  projectId:         import.meta.env.VITE_FIREBASE_PROJECT_ID         || 'drishti-link',
  storageBucket:     import.meta.env.VITE_FIREBASE_STORAGE_BUCKET     || 'drishti-link.firebasestorage.app',
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || '176369639596',
  appId:             import.meta.env.VITE_FIREBASE_APP_ID             || '1:176369639596:web:045634643ca55b38e7ff09',
};

if (!firebaseConfig.apiKey) {
  console.error(
    '[Drishti-Link] VITE_FIREBASE_API_KEY is not set. ' +
    'Create guardian_dashboard/.env and add VITE_FIREBASE_API_KEY=<your_key>'
  );
}

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize core services
export const auth = getAuth(app);
export const db   = getFirestore(app);
export const rtdb = getDatabase(app);

// Messaging — only available in browsers that support it (not all do)
export let messaging = null;

export const initMessaging = async () => {
  try {
    const supported = await isSupported();
    if (supported) {
      messaging = getMessaging(app);
    }
  } catch {
    // Silently skip — messaging is non-critical
  }
};

initMessaging();

export default app;
