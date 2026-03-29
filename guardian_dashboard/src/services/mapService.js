import { doc, onSnapshot } from 'firebase/firestore';
import { db } from '../config/firebase';

/**
 * Interpolates smoothly between old and new location.
 * Used inside a requestAnimationFrame loop by the React UI components.
 */
export const smoothLocationUpdate = (newLocation, previousLocation, progress) => {
  if (!previousLocation) return newLocation;
  
  // Progress is a float between 0.0 and 1.0
  const easeInOutCubic = progress < 0.5 ? 4 * progress * progress * progress : 1 - Math.pow(-2 * Math.max(0, Math.min(1, progress)) + 2, 3) / 2;

  return {
    lat: previousLocation.lat + (newLocation.lat - previousLocation.lat) * easeInOutCubic,
    lng: previousLocation.lng + (newLocation.lng - previousLocation.lng) * easeInOutCubic,
  };
};

/**
 * Subscribes to the live `route_points` array and builds a GeoJSON Linestring representing walked path.
 * Returns unsubscribe function.
 */
export const buildUserPath = (sessionId, onPathUpdate) => {
  if (!sessionId) return () => {};

  const docRef = doc(db, 'sessions', sessionId);
  
  return onSnapshot(docRef, (docSnap) => {
     if (docSnap.exists()) {
        const data = docSnap.data();
        const routePoints = data.route_points || [];
        
        // Build GeoJSON Object for Mapbox/Google Maps
        const coordinates = routePoints
           .filter(p => p && p.latitude && p.longitude)
           .map(p => [p.longitude, p.latitude]);
           
        // Basic mapping, color coding can be augmented if alert history is cross-referenced
        onPathUpdate({
           type: "Feature",
           properties: {
             // Green by default, overrides/warnings mapped externally via alert hook
             color: "#22c55e",
             session_id: sessionId
           },
           geometry: {
             type: "LineString",
             coordinates: coordinates
           }
        });
     }
  });
};

/**
 * Simple density-based spatial clustering for rendering markers
 * Groups alerts that are very close to each other.
 */
export const getHazardClusters = (alerts, clusterRadiusMeters = 50) => {
  if (!alerts || alerts.length === 0) return [];

  const clusters = [];

  // Very basic greedy clustering algorithm for UI performance
  alerts.forEach(alert => {
    if (!alert.location) return;

    let addedToCluster = false;
    for (const cluster of clusters) {
       const dist = getDistanceMeters(
         alert.location.latitude, alert.location.longitude,
         cluster.centerLat, cluster.centerLng
       );

       if (dist <= clusterRadiusMeters) {
          cluster.points.push(alert);
          // Recalculate centroid
          cluster.centerLat = (cluster.centerLat * (cluster.points.length - 1) + alert.location.latitude) / cluster.points.length;
          cluster.centerLng = (cluster.centerLng * (cluster.points.length - 1) + alert.location.longitude) / cluster.points.length;
          
          // Determine dominant type based on highest severity
          if (alert.type === 'override') cluster.dominantType = 'override';
          else if (alert.type === 'warning' && cluster.dominantType !== 'override') cluster.dominantType = 'warning';
          
          addedToCluster = true;
          break;
       }
    }

    if (!addedToCluster) {
       clusters.push({
         id: alert.id,
         centerLat: alert.location.latitude,
         centerLng: alert.location.longitude,
         points: [alert],
         dominantType: alert.type
       });
    }
  });

  return clusters;
};

// Helper inside mapService to avoid circular deps
const getDistanceMeters = (lat1, lon1, lat2, lon2) => {
  const R = 6371e3;
  const p1 = lat1 * Math.PI/180;
  const p2 = lat2 * Math.PI/180;
  const dp = (lat2-lat1) * Math.PI/180;
  const dl = (lon2-lon1) * Math.PI/180;
  const a = Math.sin(dp/2) * Math.sin(dp/2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl/2) * Math.sin(dl/2);
  return R * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)));
};
