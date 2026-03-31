// src/config/apiConfig.js
export const API_CONFIG = {
  BASE_URL: 'https://rtrp1-production.up.railway.app',
  ENDPOINTS: {
    SOS_TRIGGER: '/api/v1/sos/trigger',
    SOS_RESOLVE: (id) => `/api/v1/sos/${id}/resolve`,
    VISION_ANALYZE: '/api/v1/analyze/frame',
  }
};
