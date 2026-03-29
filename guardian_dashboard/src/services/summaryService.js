import { collection, query, where, getDocs, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '../config/firebase';

/**
 * Generates an end-of-day summary analyzing all sessions.
 * Optionally hooked up to a Cloud Function cron job, but perfectly viable 
 * to be triggered from the Dashboard manually or on first load the next day.
 */
export const generateDailySummary = async (userId, targetDate) => {
  try {
    // 1. Establish time bounds
    const startOfDay = new Date(targetDate);
    startOfDay.setHours(0, 0, 0, 0);
    
    const endOfDay = new Date(targetDate);
    endOfDay.setHours(23, 59, 59, 999);

    // 2. Query sessions within bounds
    const sessionsRef = collection(db, 'sessions');
    const q = query(
      sessionsRef,
      where('user_id', '==', userId),
      where('start_time', '>=', startOfDay),
      where('start_time', '<=', endOfDay) // Requires composite index dynamically or via array sort if simple
    );

    const snapshot = await getDocs(q);
    
    if (snapshot.empty) {
       return { message: "No walks recorded today." };
    }

    // 3. Aggregate totals
    let totalDistance = 0;
    let totalTimeMins = 0;
    let totalAlerts = 0;
    let totalOverrides = 0;
    let sosTriggered = false;

    snapshot.docs.forEach(docSnap => {
        const data = docSnap.data().summary || {};
        totalDistance += (data.distance_km || 0);
        totalTimeMins += (data.duration_minutes || 0);
        totalAlerts += (data.alerts_count || 0);
        totalOverrides += (data.overrides_count || 0);
        if (data.sos_triggered) sosTriggered = true;
    });

    // 4. Generate Human-readable statement (Hindi/Hinglish representation)
    const distanceStr = totalDistance.toFixed(1);
    const timeStr = Math.round(totalTimeMins);
    
    let summaryText = `Arjun aaj ${distanceStr}km chale lagbhag ${timeStr} minute. `;
    summaryText += `${totalAlerts} warnings, ${totalOverrides} emergencies aayi. `;
    
    if (sosTriggered) {
        summaryText += "Ek SOS incident bhi hua the. Dhyan rakhein. ⚠️";
    } else if (totalOverrides > 3) {
        summaryText += "Kuch dangerous situations thi, par safe raha. 🟠";
    } else {
        summaryText += "Sab safe raha. 🟢";
    }

    // 5. Save the generated summary
    const summaryData = {
       user_id: userId,
       date: startOfDay,
       distance_km: totalDistance,
       duration_minutes: totalTimeMins,
       alerts: totalAlerts,
       overrides: totalOverrides,
       summary_message: summaryText,
       created_at: serverTimestamp()
    };

    await addDoc(collection(db, `users/${userId}/daily_summaries`), summaryData);
    
    // NOTE: In production, writing this document triggers 
    // a backend Firebase function to dispatch the daily Email via SendGrid or Firebase Extensions

    return summaryData;

  } catch (error) {
    console.error("Daily Summary Generator logic failed:", error);
    throw error;
  }
};
