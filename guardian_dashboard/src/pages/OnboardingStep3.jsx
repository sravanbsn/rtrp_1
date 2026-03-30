// src/pages/OnboardingStep3.jsx — Mark Safe Zones + finish setup
import { useState, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Search, Plus, Trash2, CheckCircle } from 'lucide-react'
import { doc, setDoc, serverTimestamp } from 'firebase/firestore'
import { db } from '../config/firebase'
import { useAuth } from '../contexts/AuthContext'
import { OnboardingHeader } from './OnboardingStep1'

const ZONE_COLORS = ['#E8871A', '#16A34A', '#2563EB', '#DC2626', '#7C3AED']

const DEFAULT_ZONES = [
  { id: 1, name: 'Ghar (Home)', color: '#16A34A', radius: 200, x: 38, y: 55 },
  { id: 2, name: 'Market', color: '#2563EB', radius: 150, x: 65, y: 40 },
]

export default function OnboardingStep3() {
  const navigate = useNavigate()
  const { currentUser, updateGuardianProfile } = useAuth()
  const [zones, setZones]         = useState(DEFAULT_ZONES)
  const [zoneName, setZoneName]   = useState('')
  const [zoneColor, setZoneColor] = useState(ZONE_COLORS[0])
  const [zoneRadius, setZoneRadius] = useState(180)
  const [searchVal, setSearchVal] = useState('')
  const [pendingPin, setPendingPin] = useState({ x: 50, y: 50 })
  const [adding, setAdding]       = useState(false)
  const [saving, setSaving]       = useState(false)
  const mapRef = useRef()

  const handleMapClick = (e) => {
    if (!mapRef.current) return
    const rect = mapRef.current.getBoundingClientRect()
    const x = ((e.clientX - rect.left)  / rect.width)  * 100
    const y = ((e.clientY - rect.top)   / rect.height) * 100
    setPendingPin({ x, y })
    setAdding(true)
  }

  const addZone = () => {
    if (!zoneName.trim()) return
    setZones(prev => [...prev, {
      id: Date.now(),
      name: zoneName,
      color: zoneColor,
      radius: zoneRadius,
      x: pendingPin.x,
      y: pendingPin.y,
    }])
    setZoneName('')
    setAdding(false)
  }

  const removeZone = (id) => setZones(prev => prev.filter(z => z.id !== id))

  const handleFinish = async () => {
    setSaving(true)
    try {
      // Save safe zones to Firestore
      if (currentUser) {
        const zonesRef = doc(db, 'safe_zones', currentUser.uid)
        await setDoc(zonesRef, {
          uid: currentUser.uid,
          zones: zones.map(z => ({
            id:     String(z.id),
            name:   z.name,
            color:  z.color,
            radius: Math.round(z.radius * 1.5),  // convert to metres
            x:      z.x,
            y:      z.y,
          })),
          updated_at: serverTimestamp(),
        })
        // Mark setup complete in guardian profile
        await updateGuardianProfile({ setup_complete: true })
      }
      navigate('/dashboard')
    } catch (err) {
      console.error('Failed to save zones:', err)
      // Navigate anyway — don't block user
      navigate('/dashboard')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="onboarding-root">
      <OnboardingHeader step={2} />
      <div className="onboarding-body">
        <motion.div className="onboarding-card"
          initial={{ opacity: 0, y: 24 }} animate={{ opacity: 1, y: 0 }}
          transition={{ duration: .4 }}>

          <h2 className="onboarding-heading">Mark Safe Zones</h2>
          <p className="onboarding-sub">
            Click anywhere on the map to drop a pin and define a safe area.
            You'll be notified if your linked user moves outside these zones.
          </p>

          {/* ── Interactive Map ─────────────────────────────── */}
          <div className="map-container" ref={mapRef} onClick={handleMapClick}>
            <div className="map-bg" />

            {/* Zones as circles */}
            {zones.map(z => (
              <div key={z.id} className="zone-circle" style={{
                left: `${z.x}%`,
                top:  `${z.y}%`,
                width:  z.radius * 1.2,
                height: z.radius * 1.2,
                marginLeft: -(z.radius * 0.6),
                marginTop:  -(z.radius * 0.6),
                borderColor: z.color,
                background: z.color + '18',
              }}>
                <div style={{
                  position: 'absolute', bottom: -22, left: '50%', transform: 'translateX(-50%)',
                  fontSize: 11, fontWeight: 700, color: z.color, whiteSpace: 'nowrap',
                  textShadow: '0 1px 3px rgba(255,255,255,.8)',
                }}>
                  {z.name}
                </div>
              </div>
            ))}

            {/* Pending pin marker */}
            {adding && (
              <div className="map-pin" style={{ left: `${pendingPin.x}%`, top: `${pendingPin.y}%` }}>
                📍
              </div>
            )}

            {/* Search bar */}
            <div className="map-controls" onClick={e => e.stopPropagation()}>
              <div style={{ position: 'relative', flex: 1 }}>
                <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                <input className="map-search"
                  placeholder="Search location or click map to drop pin…"
                  value={searchVal}
                  onClick={e => e.stopPropagation()}
                  onChange={e => setSearchVal(e.target.value)}
                />
              </div>
            </div>

            {/* Tip overlay */}
            {!adding && zones.length < 3 && (
              <div style={{
                position: 'absolute', bottom: 16, left: '50%', transform: 'translateX(-50%)',
                background: 'rgba(13,27,46,.75)', color: 'white', fontSize: 12, fontWeight: 600,
                padding: '8px 16px', borderRadius: 20, whiteSpace: 'nowrap',
                backdropFilter: 'blur(8px)',
              }}>
                👆 Click the map to drop a pin
              </div>
            )}
          </div>

          {/* ── Add Zone Form ──────────────────────────────── */}
          {adding && (
            <motion.div
              initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
              style={{
                background: 'var(--off-white)', borderRadius: 'var(--radius-lg)',
                padding: 20, marginBottom: 20, border: '1.5px solid #E8EDF5',
              }}
              onClick={e => e.stopPropagation()}>
              <h4 style={{ fontSize: 14, fontWeight: 700, marginBottom: 14 }}>Name this zone</h4>
              <div className="zone-form">
                <div className="zone-form-row" style={{ alignItems: 'center' }}>
                  <div style={{ flex: 1 }}>
                    <input className="form-input" placeholder="e.g. Ghar, Market, Hospital"
                      value={zoneName} onChange={e => setZoneName(e.target.value)}
                      style={{ height: 40 }}
                    />
                  </div>
                  <div className="color-options">
                    {ZONE_COLORS.map(c => (
                      <div key={c} className={`color-swatch ${zoneColor === c ? 'selected' : ''}`}
                        style={{ background: c }} onClick={() => setZoneColor(c)} />
                    ))}
                  </div>
                </div>

                <div>
                  <label style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)',
                    display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
                    <span>Radius</span>
                    <span style={{ color: 'var(--saffron)' }}>{Math.round(zoneRadius * 1.5)}m</span>
                  </label>
                  <input type="range" className="radius-slider" min={60} max={300}
                    value={zoneRadius} onChange={e => setZoneRadius(+e.target.value)} />
                </div>

                <div style={{ display: 'flex', gap: 10 }}>
                  <button className="btn btn-primary" style={{ height: 40, fontSize: 13 }}
                    onClick={addZone} disabled={!zoneName.trim()}>
                    <Plus size={15} /> Add Zone
                  </button>
                  <button className="btn btn-outline" style={{ height: 40, fontSize: 13 }}
                    onClick={() => setAdding(false)}>
                    Cancel
                  </button>
                </div>
              </div>
            </motion.div>
          )}

          {/* ── Saved Zones List ───────────────────────────── */}
          <div className="saved-zones">
            <h4 style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-secondary)',
              letterSpacing: .5, marginBottom: 8 }}>
              SAVED ZONES ({zones.length})
            </h4>
            {zones.map(z => (
              <motion.div key={z.id} className="zone-chip"
                initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }}>
                <div className="zone-chip-dot" style={{ background: z.color }} />
                <span style={{ flex: 1 }}>{z.name}</span>
                <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                  ~{Math.round(z.radius * 1.5)}m radius
                </span>
                <button style={{ background: 'none', border: 'none', cursor: 'pointer',
                  color: 'var(--text-muted)', padding: 4, display: 'flex' }}
                  onClick={() => removeZone(z.id)}>
                  <Trash2 size={14} />
                </button>
              </motion.div>
            ))}
          </div>

          {/* ── Actions ────────────────────────────────────── */}
          <div style={{ display: 'flex', gap: 12, marginTop: 32 }}>
            <button className="btn btn-outline" style={{ maxWidth: 120 }}
              onClick={() => navigate('/setup/alerts')}>
              ← Back
            </button>
            <button
              id="finish-setup-btn"
              className={`btn btn-primary ${saving ? 'btn-loading' : ''}`}
              onClick={handleFinish}
              disabled={saving}
            >
              {!saving && <><CheckCircle size={18} /> Finish Setup → Go to Dashboard</>}
            </button>
          </div>
        </motion.div>
      </div>
    </div>
  )
}
