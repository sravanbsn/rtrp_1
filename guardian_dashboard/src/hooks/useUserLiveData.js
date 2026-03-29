/**
 * @typedef {Object} Location
 * @property {number} lat
 * @property {number} lng
 * @property {number} timestamp
 * @property {number} accuracy
 */

/**
 * @typedef {Object} LiveData
 * @property {string} status 'active' | 'paused' | 'ended' | 'sos' | 'offline'
 * @property {number} current_pc_score
 * @property {string} current_decision
 * @property {string} current_hazard
 * @property {Location} last_location
 * @property {Object} device_info
 * @property {boolean} isOffline
 */

import { useState, useEffect, useRef } from 'react';
import { ref, onValue } from 'firebase/database';
import { rtdb } from '../config/firebase';

/**
 * Hook to stream live navigation telemetry from Realtime Database
 * @param {string} sessionId 
 * @returns {{ data: LiveData | null, loading: boolean, error: Error | null }}
 */
export const useUserLiveData = (sessionId) => {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  
  const offlineTimerRef = useRef(null);

  useEffect(() => {
    if (!sessionId) {
      setLoading(false);
      setData(null);
      return;
    }

    setLoading(true);
    const sessionRef = ref(rtdb, `live_sessions/${sessionId}`);

    const unsubscribe = onValue(sessionRef, (snapshot) => {
      if (snapshot.exists()) {
        const val = snapshot.val();
        
        // Ensure interpolation flag is clear
        setData({ ...val, isOffline: false });
        setError(null);
        setLoading(false);

        // Reset offline watchdog timer (10s threshold)
        if (offlineTimerRef.current) clearTimeout(offlineTimerRef.current);
        offlineTimerRef.current = setTimeout(() => {
          setData(prev => prev ? { ...prev, isOffline: true, status: 'offline' } : null);
        }, 10000);

      } else {
        setData(null);
        setLoading(false);
      }
    }, (err) => {
      console.error("RTDB Subscription Error:", err);
      setError(err);
      setLoading(false);
    });

    return () => {
      unsubscribe();
      if (offlineTimerRef.current) clearTimeout(offlineTimerRef.current);
    };
  }, [sessionId]);

  return { data, loading, error };
};
