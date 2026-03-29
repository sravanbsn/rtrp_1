// src/components/ProtectedRoute.jsx
import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';

/**
 * Guards routes that require a fully-set-up guardian account.
 * States handled:
 *   - Not logged in                 → redirect to /login
 *   - Logged in, no guardian profile → mid-onboarding, allow /setup routes
 *     but redirect /dashboard etc back to /setup/link
 *   - Fully set up guardian         → allow access
 */
const ProtectedRoute = ({ children }) => {
  const { currentUser, isGuardian } = useAuth();
  const location = useLocation();

  if (!currentUser) {
    // Not logged in at all – send to login, remember where they were going
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if (!isGuardian) {
    // Logged in but no guardian profile yet → push them through onboarding
    return <Navigate to="/setup/link" replace />;
  }

  return children;
};

export default ProtectedRoute;
