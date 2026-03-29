import { doc, updateDoc, collection, addDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';
import { ref, update } from 'firebase/database';
import { db, rtdb } from '../config/firebase';
import { getStorage, ref as storageRef, uploadBytes, getDownloadURL } from 'firebase/storage';

export const updateNotificationPreferences = async (guardianId, newPrefs) => {
  try {
    const docRef = doc(db, 'guardians', guardianId);
    
    // Validate: SOS is always true
    const validatedPrefs = {
      ...newPrefs,
      sos: true 
    };

    await updateDoc(docRef, {
      notification_prefs: validatedPrefs
    });
    
  } catch (error) {
    console.error("Fail to update preferences:", error);
    throw error;
  }
};

export const addSafeZone = async (userId, zoneData) => {
  try {
    const zonesRef = collection(db, `users/${userId}/safe_zones`);
    
    const validatedZone = {
      name: zoneData.name,
      center: {
        lat: zoneData.lat,
        lng: zoneData.lng
      },
      radius_meters: zoneData.radius_meters || 100,
      active: true,
      created_at: serverTimestamp()
    };

    const docRef = await addDoc(zonesRef, validatedZone);
    return { id: docRef.id, ...validatedZone };
  } catch (error) {
    console.error("Add Safe Zone Error:", error);
    throw error;
  }
};

export const removeSafeZone = async (userId, zoneId) => {
  try {
    const zoneRef = doc(db, `users/${userId}/safe_zones`, zoneId);
    await deleteDoc(zoneRef);
  } catch (error) {
    console.error("Delete Safe Zone Error:", error);
    throw error;
  }
};

export const acknowledgeSOSResponse = async (sosId, sessionId, guardianId) => {
  try {
    // 1. Update Firestore
    const sosRef = doc(db, 'sos_events', sosId);
    await updateDoc(sosRef, {
       guardian_responded_at: serverTimestamp()
    });

    // 2. Update RTDB (letting the mobile device know response is active)
    const sessionRef = ref(rtdb, `live_sessions/${sessionId}`);
    await update(sessionRef, {
       'sos_status': 'guardian_en_route',
       'guardian_eta_mins': 5, // placeholder logic
       'updated_at': Date.now()
    });

    // NOTE: Cloud Function listens to `sos_events` update to trigger FCM to the user:
    // "Guardian aa raha hai."

  } catch (error) {
     console.error("ACK SOS Error:", error);
     throw error;
  }
};

export const sendVoiceNote = async (userId, guardianId, audioBlob) => {
  try {
    // Upload standard web blob to Storage
    const storage = getStorage();
    const filePath = `voice_notes/${userId}/${guardianId}_${Date.now()}.m4a`;
    const sRef = storageRef(storage, filePath);
    
    const snapshot = await uploadBytes(sRef, audioBlob);
    const audioUrl = await getDownloadURL(snapshot.ref);

    // Write to a messages collection which triggers FCM via backend
    const msgsRef = collection(db, 'voice_messages');
    await addDoc(msgsRef, {
      from: guardianId,
      to: userId,
      audio_url: audioUrl,
      timestamp: serverTimestamp(),
      played: false
    });

    return audioUrl;
  } catch (error) {
    console.error("Send Voice Note Error:", error);
    throw error;
  }
};
