// src/services/sosService.js
// Lean SOS integration — Dashboard ↔ Railway backend.
// No Twilio / SMS needed. Signal flow: Phone → Railway → Firebase RTDB → Dashboard.
import { API_CONFIG } from '../config/apiConfig';

const BASE = API_CONFIG.BASE_URL;

/**
 * Fetch the current status of an SOS alert from Railway.
 * The dashboard primarily receives SOS events via Firebase RTDB (real-time),
 * but this can be used as a polling fallback or for status hydration.
 */
export const getSosStatus = async (alertId) => {
  const res = await fetch(`${BASE}/api/v1/sos/${alertId}`, {
    method: 'GET',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) throw new Error(`getSosStatus failed: ${res.status}`);
  return res.json();
};

/**
 * Resolve / acknowledge an active SOS from the guardian dashboard.
 * Calls Railway which then:
 *   1. Updates Firestore `alerts/{alertId}` → resolved: true
 *   2. Resets Firebase RTDB `live_sessions/{userId}/status` → "navigating"
 */
export const resolveSos = async (alertId, userId, resolvedBy = 'guardian') => {
  const url = `${BASE}/api/v1/sos/${alertId}/resolve?user_id=${encodeURIComponent(userId)}&resolved_by=${resolvedBy}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) throw new Error(`resolveSos failed: ${res.status}`);
  return res.json();
};
