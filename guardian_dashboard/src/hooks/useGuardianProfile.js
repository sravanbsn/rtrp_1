import { useState, useEffect } from 'react';
import { doc, getDoc, onSnapshot } from 'firebase/firestore';
import { db } from '../config/firebase';
import { useAuth } from './useAuth';

/**
 * Hook to simultaneously fetch and watch the Guardian's profile 
 * and their linked User's profile (profile + adaptive_profile).
 */
export const useGuardianProfile = () => {
  const { currentUser } = useAuth();
  
  const [guardian, setGuardian] = useState(null);
  const [linkedUser, setLinkedUser] = useState(null);
  
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!currentUser) {
      setLoading(false);
      return;
    }

    let unsubscribeUser = () => {};

    // First fetch Guardian profile
    const fetchProfiles = async () => {
      try {
        const guardianRef = doc(db, 'guardians', currentUser.uid);
        const guardianSnap = await getDoc(guardianRef);
        
        if (!guardianSnap.exists()) {
           throw new Error("Guardian profile missing");
        }

        const guardianData = guardianSnap.data();
        setGuardian(guardianData);

        const linkedUserId = guardianData.user_id;

        if (linkedUserId) {
           // Subscribe to linked user's document for live updates
           const userRef = doc(db, 'users', linkedUserId);
           unsubscribeUser = onSnapshot(userRef, (userSnap) => {
              if (userSnap.exists()) {
                 setLinkedUser({ id: userSnap.id, ...userSnap.data() });
              }
           });
        }
        
        setLoading(false);

      } catch (err) {
        console.error("Profile Fetch Error:", err);
        setError(err);
        setLoading(false);
      }
    };

    fetchProfiles();

    return () => unsubscribeUser();
  }, [currentUser]);

  return { guardian, linkedUser, loading, error };
};
