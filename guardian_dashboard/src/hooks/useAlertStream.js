/**
 * @typedef {Object} Alert
 * @property {string} id
 * @property {string} type 'override' | 'warning' | 'area_memory' | 'sos'
 * @property {string} hazard_type
 * @property {number} pc_score
 * @property {string} plain_description
 * @property {Object} location
 * @property {any} timestamp
 */

import { useState, useEffect } from 'react';
import { collection, query, where, orderBy, limit, onSnapshot } from 'firebase/firestore';
import { db } from '../config/firebase';

/**
 * Hook to stream navigational alerts instantly from Firestore
 * @param {string} userId 
 * @param {string} [sessionId] Optional filter by active session
 * @param {string} [alertType] Optional filter by alert type
 */
export const useAlertStream = (userId, sessionId = null, alertType = null) => {
  const [alerts, setAlerts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Track the most recent alert ID to trigger animation flags safely without re-renders
  const [newAlertTrigger, setNewAlertTrigger] = useState(null);

  useEffect(() => {
    if (!userId) {
      setLoading(false);
      return;
    }

    let q = query(
      collection(db, 'alerts'),
      where('user_id', '==', userId),
      orderBy('timestamp', 'desc'),
      limit(50)
    );

    // Apply composite index constraints
    if (sessionId) {
      q = query(q, where('session_id', '==', sessionId));
    }
    if (alertType) {
      q = query(q, where('type', '==', alertType));
    }

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const parsedAlerts = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));

      setAlerts((prev) => {
        // Simple heuristic: if the top ID changes and we already had alerts, it's new
        if (prev.length > 0 && parsedAlerts.length > 0 && prev[0].id !== parsedAlerts[0].id) {
          setNewAlertTrigger(parsedAlerts[0]);
        }
        return parsedAlerts;
      });
      
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Alerts Subscription Error:", err);
      setError(err);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [userId, sessionId, alertType]);

  return { alerts, loading, error, newAlertTrigger };
};
