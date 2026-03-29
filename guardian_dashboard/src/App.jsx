<<<<<<< HEAD
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import LoginPage         from './pages/LoginPage'
import ForgotPasswordFlow from './pages/ForgotPasswordFlow'
import OnboardingStep1   from './pages/OnboardingStep1'
import OnboardingStep2   from './pages/OnboardingStep2'
import OnboardingStep3   from './pages/OnboardingStep3'
import Dashboard         from './pages/Dashboard'
import AlertHistory      from './pages/AlertHistory'
import SafeZones         from './pages/SafeZones'
import ProtectedRoute      from './components/ProtectedRoute'
import './index.css'

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/"              element={<Navigate to="/login" replace />} />
        <Route path="/login"         element={<LoginPage />} />
        <Route path="/forgot"        element={<ForgotPasswordFlow />} />
        <Route path="/setup/link"    element={<OnboardingStep1 />} />
        <Route path="/setup/alerts"  element={<OnboardingStep2 />} />
        <Route path="/setup/zones"   element={<OnboardingStep3 />} />
        <Route path="/dashboard"     element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
        <Route path="/alerts"        element={<ProtectedRoute><AlertHistory /></ProtectedRoute>} />
        <Route path="/zones"         element={<ProtectedRoute><SafeZones /></ProtectedRoute>} />
      </Routes>
    </BrowserRouter>
  )
=======
import { createBrowserRouter, RouterProvider, Navigate } from 'react-router-dom';
import { useAuth } from './contexts/AuthContext';
import LoginPage from './pages/LoginPage';
import ForgotPasswordFlow from './pages/ForgotPasswordFlow';
import OnboardingStep1 from './pages/OnboardingStep1';
import OnboardingStep2 from './pages/OnboardingStep2';
import OnboardingStep3 from './pages/OnboardingStep3';
import Dashboard from './pages/Dashboard';
import AlertHistory from './pages/AlertHistory';
import SafeZones from './pages/SafeZones';
import SignupPage from './pages/SignupPage'; // Assuming you have a signup page
import './index.css';

const ProtectedRoute = ({ children }) => {
  const { isAuthenticated, loading } = useAuth();

  if (loading) {
    return <div>Loading...</div>; // Or a spinner component
  }

  if (!isAuthenticated()) {
    return <Navigate to="/login" replace />;
  }

  return children;
};

const GuestRoute = ({ children }) => {
  const { isAuthenticated, loading } = useAuth();

  if (loading) {
    return <div>Loading...</div>; // Or a spinner component
  }

  if (isAuthenticated()) {
    return <Navigate to="/dashboard" replace />;
  }

  return children;
};

const router = createBrowserRouter([
  {
    path: '/',
    element: <ProtectedRoute><Dashboard /></ProtectedRoute>,
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
]);

function App() {
  return <RouterProvider router={router} />;
>>>>>>> 3c44fd109675a7869954568aacbcf4cb55ac6532
}

export default App;
