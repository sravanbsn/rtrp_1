// src/pages/Dashboard.jsx — Guardian Dashboard with real Firebase data
import { useState, useEffect, useCallback, useRef } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ref as rtdbRef, onValue, off } from 'firebase/database'
import { collection, query, where, orderBy, limit, onSnapshot } from 'firebase/firestore'
import { Toaster, toast } from 'react-hot-toast'
import Navbar    from '../components/Navbar'
import Sidebar   from '../components/Sidebar'
import MapPanel  from '../components/MapPanel'
import LiveFeed  from '../components/LiveFeed'
import SosOverlay from '../components/SosOverlay'
import { rtdb, db } from '../config/firebase'
import { useAuth } from '../contexts/AuthContext'
import { resolveSos } from '../services/sosService'
import '../dashboard.css'

const DEFAULT_USER = { id: 1, initials: 'AR', name: 'Arjun Sharma', status: 'Offline', color: '#E8871A' }

export default function Dashboard() {
  const { currentUser, guardianProfile } = useAuth()

  const [activeUser,    setActiveUser]  = useState(DEFAULT_USER)
  const [showPopup,     setShowPopup]   = useState(false)
  const [showSOS,       setShowSOS]     = useState(false)
  const [riskValue,     setRiskValue]   = useState(0)
  const [bellCount,     setBellCount]   = useState(0)
  const [sessionData,   setSessionData] = useState(null)   // live RTDB session
  const [recentAlerts,  setRecentAlerts] = useState([])
  const [noUserLinked,  setNoUserLinked] = useState(false)

  const sosRef = useRef(false) // prevent duplicate SOS toasts

  // ── Real-time session listener (Firebase RTDB) ─────────────────
  useEffect(() => {
    if (!guardianProfile?.linked_user_uid) {
      setNoUserLinked(true)
      return
    }
    setNoUserLinked(false)
    const uid       = guardianProfile.linked_user_uid
    const sessionDb = rtdbRef(rtdb, `live_sessions/${uid}`)

    const unsubscribe = onValue(sessionDb, (snapshot) => {
      const data = snapshot.val()
      if (!data) {
        setSessionData(null)
        setActiveUser(prev => ({ ...prev, status: 'Offline' }))
        return
      }

      setSessionData(data)

      // Update active user status
      setActiveUser(prev => ({
        ...prev,
        status: data.status === 'sos' ? '🆘 SOS' : data.status === 'navigating' ? 'Navigating' : 'Online',
      }))

      // Update risk value from Pc score
      if (data.pc_score !== undefined) {
        setRiskValue(Math.round(data.pc_score * 100))
      }

      // SOS detection
      if (data.status === 'sos' && !sosRef.current) {
        sosRef.current = true
        setShowSOS(true)
        toast.error('🆘 SOS alert! Arjun needs help!', { duration: 10000 })
        setBellCount(c => c + 1)
      } else if (data.status !== 'sos') {
        sosRef.current = false
      }
    })

    return () => off(sessionDb)
  }, [guardianProfile?.linked_user_uid])

  // ── Real-time alert listener (Firestore) ───────────────────────
  useEffect(() => {
    if (!guardianProfile?.linked_user_uid) return
    const uid = guardianProfile.linked_user_uid

    const q = query(
      collection(db, 'alerts'),
      where('user_id', '==', uid),
      orderBy('created_at', 'desc'),
      limit(20)
    )

    const unsub = onSnapshot(q, (snap) => {
      const alerts = snap.docs.map(d => ({ id: d.id, ...d.data() }))
      setRecentAlerts(alerts)

      // New override/SOS → bell + popup
      if (snap.docChanges().some(c => c.type === 'added' && ['override', 'sos'].includes(c.doc.data().type))) {
        setShowPopup(true)
        setBellCount(c => c + 1)
      }
    }, (err) => {
      console.warn('Alert listener error:', err)
    })

    return () => unsub()
  }, [guardianProfile?.linked_user_uid])

  const handleDismissPopup  = useCallback(() => setShowPopup(false), [])
  const handleSOS           = useCallback(() => { setShowSOS(true); setShowPopup(false) }, [])
  const handleAcknowledge = useCallback(async () => {
    if (sessionData?.sos_alert_id) {
      try {
        // Call Railway directly — it resets RTDB status to 'navigating'
        await resolveSos(
          sessionData.sos_alert_id,
          guardianProfile?.linked_user_uid ?? '',
          'guardian'
        )
        toast.success('Response confirmed. User is being notified.')
      } catch (err) {
        console.warn('resolveSos Railway call failed:', err)
        toast.error('Failed to sync with Railway backend.')
      }
    }
    setShowSOS(false)
    sosRef.current = false
  }, [sessionData, guardianProfile])

  // ── No user linked state ───────────────────────────────────────
  if (noUserLinked) {
    return (
      <div className="dash-root">
        <Toaster position="top-right" />
        <Navbar activeUser={activeUser} onUserChange={setActiveUser}
          isSOS={false} onBellClick={() => setBellCount(0)} bellCount={0} />
        <div className="dash-body">
          <Sidebar activeUser={activeUser} />
          <div className="dash-main" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <motion.div
              initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }}
              style={{ textAlign: 'center', maxWidth: 400, padding: 40 }}
            >
              <div style={{ fontSize: 64, marginBottom: 24 }}>🔗</div>
              <h2 style={{ fontSize: 22, fontWeight: 800, marginBottom: 12 }}>No User Linked</h2>
              <p style={{ color: 'rgba(255,255,255,0.5)', lineHeight: 1.7, marginBottom: 28 }}>
                Link a Drishti-Link user to start monitoring their location, hazard alerts, and SOS events in real time.
              </p>
              <button className="btn btn-primary" onClick={() => window.location.href = '/setup/link'}>
                🔗 Link a User
              </button>
            </motion.div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="dash-root">
      <Toaster position="top-right" toastOptions={{
        style: { background: '#1a2d45', color: '#fff', border: '1px solid rgba(255,255,255,0.1)' }
      }} />

      <Navbar
        activeUser={activeUser}
        onUserChange={setActiveUser}
        isSOS={showSOS}
        onBellClick={() => setBellCount(0)}
        bellCount={bellCount}
      />

      <div className="dash-body">
        <Sidebar activeUser={activeUser} />

        <div className="dash-main">
          <div className="dash-columns">
            <MapPanel
              showPopup={showPopup}
              onDismissPopup={handleDismissPopup}
              sessionData={sessionData}
            />
            <LiveFeed
              riskValue={riskValue}
              onSOS={handleSOS}
              sessionData={sessionData}
              recentAlerts={recentAlerts}
            />
          </div>
        </div>
      </div>

      {/* SOS full screen overlay */}
      <AnimatePresence>
        {showSOS && <SosOverlay onAcknowledge={handleAcknowledge} />}
      </AnimatePresence>
    </div>
  )
}
