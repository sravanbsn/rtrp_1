import { getToken, onMessage } from 'firebase/messaging';
import { doc, updateDoc, arrayUnion } from 'firebase/firestore';
import { messaging, db } from '../config/firebase';

// Mock Web Audio Context implementation reference for sounds
const SOS_AUDIO = '/sounds/sos_alarm.mp3';
const WARNING_AUDIO = '/sounds/soft_chime.mp3';
const OVERRIDE_AUDIO = '/sounds/medium_tone.mp3';

// Keep track of SOS loop
let sosAudioLoop = null;

export const playAlertSound = (type) => {
  try {
    if (type === 'sos') {
       if (!sosAudioLoop) {
          sosAudioLoop = new Audio(SOS_AUDIO);
          sosAudioLoop.loop = true;
          sosAudioLoop.play().catch(e => console.warn("Audio play blocked by browser:", e));
       }
    } else if (type === 'override') {
       const audio = new Audio(OVERRIDE_AUDIO);
       audio.play().catch(e => console.warn("Audio play blocked by browser:", e));
    } else if (type === 'warning') {
       const audio = new Audio(WARNING_AUDIO);
       audio.play().catch(e => console.warn("Audio play blocked by browser:", e));
    }
  } catch (err) {
    console.error("Audio playback failed:", err);
  }
};

export const stopSOSSound = () => {
    if (sosAudioLoop) {
       sosAudioLoop.pause();
       sosAudioLoop.currentTime = 0;
       sosAudioLoop = null;
    }
};

export const requestNotificationPermission = async (guardianId) => {
  if (!messaging) return false;

  try {
    const permission = await Notification.requestPermission();
    if (permission === 'granted') {
      // NOTE: Replace with actual VAPID key in production
      const token = await getToken(messaging, { 
        vapidKey: 'BM-O7F9o55D5rV9v6NbxLMBH8sY-EaF8-BvO9iK0I-7i_h729D-D8hB_sI9xN-hZ9_d98d8M-p7O4lP9d8j' 
      });

      if (token) {
        // Save FCM token to Guardian doc
        const guardianRef = doc(db, 'guardians', guardianId);
        await updateDoc(guardianRef, {
          fcm_tokens: arrayUnion(token)
        });
        console.log("FCM Token saved successfully.");
        return true;
      }
    }
    return false;
  } catch (error) {
    console.error("FCM Permission error:", error);
    return false;
  }
};

/**
 * Initializes foreground listener for FCM pushes.
 * Returns the unsubscribe function.
 */
export const handleForegroundMessage = (dispatchToast) => {
  if (!messaging) return () => {};

  return onMessage(messaging, (payload) => {
    console.log("Received foreground message:", payload);
    
    const { notification, data } = payload;
    const type = data?.type || 'session';

    // Dispatch custom UI toasts rather than native browser alerts if app is open
    if (type === 'sos') {
       playAlertSound('sos');
       // The SOS modal listener in the React tree will handle the UI inherently,
       // but we trigger sound and dispatch a structural flag here
       dispatchToast({ render_type: 'modal', title: notification.title, body: notification.body });
    } 
    else if (type === 'override') {
       playAlertSound('override');
       dispatchToast({ render_type: 'banner', title: notification.title, body: notification.body, persist: true });
    }
    else if (type === 'warning') {
       playAlertSound('warning');
       dispatchToast({ render_type: 'toast', title: notification.title, body: notification.body, duration: 5000 });
    }
    else {
       // Session updates / Generic
       dispatchToast({ render_type: 'toast', title: notification.title, body: notification.body, duration: 3000 });
    }
  });
};

/**
 * Service Worker file (firebase-messaging-sw.js) handles background messages automatically.
 * It will display system notifications containing Action Buttons.
 * This stub represents the logic that goes inside the separate SW file for documentation context.
 */
export const handleBackgroundMessage = () => {
   /*
   importScripts('https://www.gstatic.com/firebasejs/9.x.x/firebase-app-compat.js');
   importScripts('https://www.gstatic.com/firebasejs/9.x.x/firebase-messaging-compat.js');

   firebase.initializeApp({ ... });
   const messaging = firebase.messaging();

   messaging.onBackgroundMessage((payload) => {
     const type = payload.data.type;
     const notificationTitle = payload.notification.title;
     
     const notificationOptions = {
       body: payload.notification.body,
       icon: '/logo192.png',
       requireInteraction: (type === 'sos' || type === 'override'), // Keeps it on screen
       actions: (type === 'sos') ? [
         { action: 'ack', title: 'Acknowledge SOS' }
       ] : []
     };
     
     return self.registration.showNotification(notificationTitle, notificationOptions);
   });
   */
};
