import { useState, useEffect, useCallback } from 'react'
import { AnimatePresence } from 'framer-motion'
import Navbar    from '../components/Navbar'
import Sidebar   from '../components/Sidebar'
import MapPanel  from '../components/MapPanel'
import LiveFeed  from '../components/LiveFeed'
import SosOverlay from '../components/SosOverlay'
import '../dashboard.css'

const DEFAULT_USER = { id:1, initials:'AR', name:'Arjun Sharma', status:'Navigating', color:'#E8871A' }

export default function Dashboard() {
  const [activeUser, setActiveUser]   = useState(DEFAULT_USER)
  const [showPopup,  setShowPopup]    = useState(false)
  const [showSOS,    setShowSOS]      = useState(false)
  const [riskValue,  setRiskValue]    = useState(12)
  const [bellCount,  setBellCount]    = useState(3)

  // Simulate risk fluctuation
  useEffect(() => {
    const iv = setInterval(() => {
      setRiskValue(v => Math.max(5, Math.min(90, v + (Math.random() - 0.45) * 6)))
    }, 3000)
    return () => clearInterval(iv)
  }, [])

  // Simulate popup every 18s
  useEffect(() => {
    const iv = setInterval(() => {
      setShowPopup(true)
      setBellCount(c => c + 1)
    }, 18000)
    // Show first popup after 4s
    const t = setTimeout(() => setShowPopup(true), 4000)
    return () => { clearInterval(iv); clearTimeout(t) }
  }, [])

  const handleDismissPopup = useCallback(() => setShowPopup(false), [])
  const handleSOS = useCallback(() => {
    setShowSOS(true)
    setShowPopup(false)
  }, [])
  const handleAcknowledge = useCallback(() => setShowSOS(false), [])

  return (
    <div className="dash-root">
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
            />
            <LiveFeed
              riskValue={Math.round(riskValue)}
              onSOS={handleSOS}
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
