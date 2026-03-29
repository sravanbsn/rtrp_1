/**
 * @typedef {Object} SessionSummary
 * @property {number} distance_km
 * @property {number} duration_minutes
 * @property {number} alerts_count
 * @property {number} overrides_count
 * @property {number} safety_score
 * @property {boolean} sos_triggered
 */

/**
 * @typedef {Object} Session
 * @property {string} id
 * @property {string} user_id
 * @property {string} status
 * @property {any} start_time
 * @property {any} end_time
 * @property {SessionSummary} summary
 */

import { useState, useEffect, useCallback } from 'react';
import { collection, query, where, orderBy, limit, getDocs, startAfter } from 'firebase/firestore';
import { db } from '../config/firebase';

const PAGE_SIZE = 20;

/**
 * Hook to fetch paginated session history for a user
 * @param {string} userId 
 */
export const useSessionHistory = (userId) => {
  const [sessions, setSessions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState(null);
  const [hasMore, setHasMore] = useState(true);
  const [lastVisible, setLastVisible] = useState(null);

  const fetchInitial = useCallback(async () => {
    if (!userId) return;
    setLoading(true);
    setError(null);

    try {
      const q = query(
        collection(db, 'sessions'),
        where('user_id', '==', userId),
        orderBy('start_time', 'desc'),
        limit(PAGE_SIZE)
      );

      const snapshot = await getDocs(q);
      const docs = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      
      setSessions(docs);
      setLastVisible(snapshot.docs[snapshot.docs.length - 1]);
      setHasMore(docs.length === PAGE_SIZE);
      
    } catch (err) {
      console.error("Session History Error:", err);
      setError(err);
    } finally {
      setLoading(false);
    }
  }, [userId]);

  useEffect(() => {
    fetchInitial();
  }, [fetchInitial]);

  const loadMore = async () => {
    if (!hasMore || loadingMore || !lastVisible || !userId) return;
    
    setLoadingMore(true);
    try {
      const q = query(
        collection(db, 'sessions'),
        where('user_id', '==', userId),
        orderBy('start_time', 'desc'),
        startAfter(lastVisible),
        limit(PAGE_SIZE)
      );

      const snapshot = await getDocs(q);
      const docs = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));

      setSessions(prev => [...prev, ...docs]);
      setLastVisible(snapshot.docs[snapshot.docs.length - 1]);
      setHasMore(docs.length === PAGE_SIZE);

    } catch (err) {
      console.error("Load More Error:", err);
      setError(err);
    } finally {
      setLoadingMore(false);
    }
  };

  return { sessions, loading, loadingMore, error, hasMore, loadMore, refresh: fetchInitial };
};
