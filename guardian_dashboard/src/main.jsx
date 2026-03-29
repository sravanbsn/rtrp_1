import React, { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
<<<<<<< HEAD
import { AuthProvider } from './hooks/useAuth.jsx'

class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }
  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }
  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: '2rem', color: 'red', fontFamily: 'monospace' }}>
          <h2>Fatal Application Error</h2>
          <pre style={{ whiteSpace: 'pre-wrap' }}>{this.state.error.message || String(this.state.error)}</pre>
          {this.state.error.stack && (
            <pre style={{ marginTop: '1rem', color: '#666', fontSize: '12px', whiteSpace: 'pre-wrap' }}>
              {this.state.error.stack}
            </pre>
          )}
        </div>
      );
    }
    return this.props.children;
  }
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <ErrorBoundary>
      <AuthProvider>
        <App />
      </AuthProvider>
    </ErrorBoundary>
=======
import { AuthProvider } from './contexts/AuthContext.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <AuthProvider>
      <App />
    </AuthProvider>
>>>>>>> 3c44fd109675a7869954568aacbcf4cb55ac6532
  </StrictMode>,
)
