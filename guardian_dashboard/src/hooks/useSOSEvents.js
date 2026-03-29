/**
 * @typedef {Object} SOSEvent
 * @property {string} id
 * @property {string} user_id
 * @property {string} session_id
 * @property {string} trigger_reason
 * @property {boolean} resolved
 * @property {any} triggered_at
 * @property {Object} location
 */

import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot } from 'firebase/firestore';
import { db } from '../config/firebase';

/**
 * Hook to instantly detect an active, unresolved SOS event for a linked user
 * @param {string} userId 
 */
export const useSOSEvents = (userId) => {
  const [activeSOS, setActiveSOS] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!userId) {
      setLoading(false);
      return;
    }

    const q = query(
      collection(db, 'sos_events'),
      where('user_id', '==', userId),
      where('resolved', '==', false)
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      if (!snapshot.empty) {
        // Return the most recent unresolved SOS
        const doc = snapshot.docs[0];
        setActiveSOS({ id: doc.id, ...doc.data() });
      } else {
        setActiveSOS(null);
      }
      setLoading(false);
    }, (err) => {
      console.error("SOS Stream Error:", err);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [userId]);

  return { activeSOS, loading };
};
