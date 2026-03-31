import { doc, updateDoc, collection, addDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';
import { ref, update } from 'firebase/database';
import { db, rtdb } from '../config/firebase';
import { getStorage, ref as storageRef, uploadBytes, getDownloadURL } from 'firebase/storage';
import { API_CONFIG } from '../config/apiConfig';

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

export const acknowledgeSOSResponse = async (sosId, sessionId, guardianId, userId) => {
  try {
    // 1. Call Backend to Resolve
    const response = await fetch(`${API_CONFIG.BASE_URL}${API_CONFIG.ENDPOINTS.SOS_RESOLVE(sosId)}?user_id=${userId}&resolved_by=guardian`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });

    if (!response.ok) {
      throw new Error(`Backend resolve failed: ${response.status}`);
    }

    // 2. Local Firestore update (backup/UI immediate feedback)
    const sosRef = doc(db, 'alerts', sosId);
    await updateDoc(sosRef, {
       guardian_responded_at: serverTimestamp(),
       resolved: true
    });

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
