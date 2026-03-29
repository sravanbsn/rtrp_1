import { useEffect, useRef } from 'react'
import { Phone, X } from 'lucide-react'

export default function AlertPopup({ onDismiss }) {
  const timerRef = useRef()

  useEffect(() => {
    timerRef.current = setTimeout(onDismiss, 8000)
    return () => clearTimeout(timerRef.current)
  }, [onDismiss])

  return (
    <div className="alert-popup">
      <div className="alert-popup-header">
        <span className="alert-popup-icon">⚠️</span>
        <span className="alert-popup-title">
          Arjun was stopped — vehicle approaching fast
        </span>
        <button onClick={onDismiss}
          style={{ background:'none', border:'none', color:'rgba(255,255,255,.4)',
            cursor:'pointer', padding:4, display:'flex' }}>
          <X size={14} />
        </button>
      </div>

      {/* Auto-dismiss timer bar */}
      <div className="alert-timer-bar">
        <div className="alert-timer-fill" />
      </div>

      <div style={{ fontSize:11, color:'rgba(255,255,255,.4)', marginBottom:10 }}>
        📍 Gandhi Nagar Junction · 2:41 PM · Auto-dismisses in 8s
      </div>

      <div className="alert-popup-actions">
        <button className="alert-dismiss-btn" onClick={onDismiss}>
          ✓ Dismiss
        </button>
        <button className="alert-call-btn">
          <Phone size={13} style={{ display:'inline', marginRight:6 }} />
          Call Arjun
        </button>
      </div>
    </div>
  )
}
