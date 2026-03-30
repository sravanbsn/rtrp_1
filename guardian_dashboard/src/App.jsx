import { createBrowserRouter, RouterProvider, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import LoginPage from './pages/LoginPage';
import SignupPage from './pages/SignupPage';
import ForgotPasswordFlow from './pages/ForgotPasswordFlow';
import OnboardingStep1 from './pages/OnboardingStep1';
import OnboardingStep2 from './pages/OnboardingStep2';
import OnboardingStep3 from './pages/OnboardingStep3';
import Dashboard from './pages/Dashboard';
import AlertHistory from './pages/AlertHistory';
import SafeZones from './pages/SafeZones';
import RouteHistory from './pages/RouteHistory';
import Settings from './pages/Settings';
import './index.css';

// ── Full-screen loading spinner ───────────────────────────────────────────────
function LoadingScreen() {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100vh',
      background: 'var(--bg-primary, #0D1B2E)',
      flexDirection: 'column',
      gap: 20,
    }}>
      <div style={{
        width: 48,
        height: 48,
        border: '3px solid rgba(255,255,255,0.1)',
        borderTopColor: '#E8871A',
        borderRadius: '50%',
        animation: 'spin 0.8s linear infinite',
      }} />
      <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 14 }}>Loading Drishti-Link…</p>
      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );
}

// ── Protected route: requires auth + guardian profile ────────────────────────
const ProtectedRoute = ({ children }) => {
  const { currentUser, guardianProfile, loading } = useAuth();

  if (loading) return <LoadingScreen />;

  if (!currentUser) {
    return <Navigate to="/login" replace />;
  }

  // User role check: non-guardians see a polite rejection
  if (guardianProfile && guardianProfile.role === 'user') {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        height: '100vh', background: '#0D1B2E', color: 'white', flexDirection: 'column', gap: 16,
      }}>
        <span style={{ fontSize: 48 }}>📱</span>
        <h2>Please use the mobile app</h2>
        <p style={{ color: 'rgba(255,255,255,0.6)' }}>
          This dashboard is for guardians. Open the Drishti-Link app on your phone.
        </p>
      </div>
    );
  }

  return children;
};

// ── Guest route: if already auth → redirect to dashboard ─────────────────────
const GuestRoute = ({ children }) => {
  const { currentUser, loading } = useAuth();

  if (loading) return <LoadingScreen />;
  if (currentUser) return <Navigate to="/dashboard" replace />;

  return children;
};

// ── Router definition ─────────────────────────────────────────────────────────
const router = createBrowserRouter([
  {
    path: '/',
    element: <Navigate to="/dashboard" replace />,
  },
  {
    path: '/login',
    element: <GuestRoute><LoginPage /></GuestRoute>,
  },
  {
    path: '/signup',
    element: <GuestRoute><SignupPage /></GuestRoute>,
  },
  {
    path: '/forgot',
    element: <ForgotPasswordFlow />,
  },
  {
    path: '/setup/link',
    element: <ProtectedRoute><OnboardingStep1 /></ProtectedRoute>,
  },
  {
    path: '/setup/alerts',
    element: <ProtectedRoute><OnboardingStep2 /></ProtectedRoute>,
  },
  {
    path: '/setup/zones',
    element: <ProtectedRoute><OnboardingStep3 /></ProtectedRoute>,
  },
  {
    path: '/dashboard',
    element: <ProtectedRoute><Dashboard /></ProtectedRoute>,
  },
  {
    path: '/alerts',
    element: <ProtectedRoute><AlertHistory /></ProtectedRoute>,
  },
  {
    path: '/zones',
    element: <ProtectedRoute><SafeZones /></ProtectedRoute>,
  },
  {
    path: '/routes',
    element: <ProtectedRoute><RouteHistory /></ProtectedRoute>,
  },
  {
    path: '/settings',
    element: <ProtectedRoute><Settings /></ProtectedRoute>,
  },
  // Catch-all
  {
    path: '*',
    element: <Navigate to="/dashboard" replace />,
  },
]);

// ── Root App — AuthProvider wraps everything ──────────────────────────────────
function App() {
  return (
    <AuthProvider>
      <RouterProvider router={router} />
    </AuthProvider>
  );
}

export default App;
