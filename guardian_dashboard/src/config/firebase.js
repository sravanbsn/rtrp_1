// src/config/firebase.js
import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getDatabase } from 'firebase/database';
import { getMessaging, isSupported } from 'firebase/messaging';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || "YOUR_FIREBASE_API_KEY",
  authDomain: "drishti-link.firebaseapp.com",
  databaseURL: "https://drishti-link-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "drishti-link",
  storageBucket: "drishti-link.firebasestorage.app",
  messagingSenderId: "176369639596",
  appId: "1:176369639596:web:045634643ca55b38e7ff09"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize core services
export const auth = getAuth(app);
export const db = getFirestore(app);
export const rtdb = getDatabase(app);

// Initialize Messaging conditionally (not supported in all browsers)
export let messaging = null;

export const initMessaging = async () => {
  try {
    const supported = await isSupported();
    if (supported) {
      messaging = getMessaging(app);
      console.log('Firebase Messaging initialized successfully');
    }
  } catch (error) {
    console.warn('Firebase Messaging not supported in this environment', error);
  }
};

initMessaging();

export default app;
