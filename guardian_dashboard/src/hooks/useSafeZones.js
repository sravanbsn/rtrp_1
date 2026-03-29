/**
 * @typedef {Object} SafeZone
 * @property {string} id
 * @property {string} name
 * @property {Object} center {lat, lng}
 * @property {number} radius_meters
 * @property {boolean} active
 */

import { useState, useEffect } from 'react';
import { collection, query, onSnapshot } from 'firebase/firestore';
import { db } from '../config/firebase';

// Helper: Haversine distance in meters
const getDistanceMeters = (lat1, lon1, lat2, lon2) => {
  const R = 6371e3; // metres
  const φ1 = lat1 * Math.PI/180;
  const φ2 = lat2 * Math.PI/180;
  const Δφ = (lat2-lat1) * Math.PI/180;
  const Δλ = (lon2-lon1) * Math.PI/180;
  const a = Math.sin(Δφ/2) * Math.sin(Δφ/2) +
          Math.cos(φ1) * Math.cos(φ2) *
          Math.sin(Δλ/2) * Math.sin(Δλ/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
};

/**
 * Hook to watch safe zones and compute if user is within bounds
 * @param {string} userId 
 * @param {{lat: number, lng: number}} currentLocation 
 */
export const useSafeZones = (userId, currentLocation) => {
  const [zones, setZones] = useState([]);
  const [loading, setLoading] = useState(true);

  // Computed state
  const [currentZone, setCurrentZone] = useState(null);
  const [isOutsideAllZones, setIsOutsideAllZones] = useState(false);

  // 1. Fetch zones
  useEffect(() => {
    if (!userId) {
      setLoading(false);
      return;
    }

    const q = query(collection(db, `users/${userId}/safe_zones`));
    
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const parsedZones = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      setZones(parsedZones);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [userId]);

  // 2. Compute bounds
  useEffect(() => {
    if (!currentLocation || zones.length === 0) {
       setCurrentZone(null);
       setIsOutsideAllZones(false);
       return;
    }

    let foundZone = null;

    for (const zone of zones) {
      if (!zone.active) continue;
      
      const distance = getDistanceMeters(
        currentLocation.lat, currentLocation.lng,
        zone.center.lat, zone.center.lng
      );

      if (distance <= zone.radius_meters) {
        foundZone = zone;
        break;
      }
    }

    setCurrentZone(foundZone);
    setIsOutsideAllZones(foundZone === null);

  }, [currentLocation, zones]);

  return { zones, currentZone, isOutsideAllZones, loading };
};
