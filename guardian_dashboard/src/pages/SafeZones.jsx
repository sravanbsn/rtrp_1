import { useState, useRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Search, Plus, Edit2, Trash2, X } from 'lucide-react'
import Navbar  from '../components/Navbar'
import Sidebar from '../components/Sidebar'
import '../dashboard.css'
import '../pages.css'

// ── Zone data ────────────────────────────────────────────────────
const INITIAL_ZONES = [
  {
    id: 1, name: 'Home',   address: 'Banjara Hills, Hyderabad',
    radius: 200, color: '#16A34A', alert: 'Leaving',
    x: 28, y: 48, emoji: '🏠',
  },
  {
    id: 2, name: 'School', address: 'Jubilee Hills, Hyderabad',
    radius: 160, color: '#2563EB', alert: 'Both',
    x: 55, y: 32, emoji: '🏫',
  },
  {
    id: 3, name: 'Market', address: 'Ameerpet, Hyderabad',
    radius: 130, color: '#7C3AED', alert: 'Entering',
    x: 70, y: 58, emoji: '🛒',
  },
]

const ZONE_COLORS = ['#16A34A','#2563EB','#7C3AED','#E8871A','#DC2626','#0891B2']
const ZONE_ALERTS = ['Leaving','Entering','Both']
const OUTSIDE_TIMES = ['5 min','10 min','15 min','30 min','1 hour']

const DEFAULT_USER = { id:1, initials:'AR', name:'Arjun Sharma', status:'Navigating', color:'#E8871A' }

// ── Zone circle on map ───────────────────────────────────────────
function ZoneCircle({ zone, selected, onClick }) {
  const diameter = zone.radius * 1.8
  return (
    <div className={`zone-overlay ${selected ? 'selected' : ''}`}
      style={{
        left: `${zone.x}%`, top: `${zone.y}%`,
        width: diameter, height: diameter,
        marginLeft: -diameter/2, marginTop: -diameter/2,
        border: `2.5px dashed ${zone.color}`,
        background: zone.color + '18',
      }}
      onClick={onClick}>
      <div className="zone-pin">{zone.emoji}</div>
      <div className="zone-label" style={{ color: zone.color }}>
        {zone.name}
      </div>
    </div>
  )
}

// ── Add Zone Form ────────────────────────────────────────────────
function AddZoneForm({ pendingPin, onSave, onCancel }) {
  const [name,    setName]    = useState('')
  const [address, setAddress] = useState('')
  const [radius,  setRadius]  = useState(200)
  const [color,   setColor]   = useState(ZONE_COLORS[0])
  const [alertT,  setAlertT]  = useState('Leaving')

  const radiusMeters = Math.round(radius * 1.5)

  const handleSave = () => {
    if (!name.trim()) return
    onSave({ name, address: address || 'Dropped pin location', radius, color, alertT })
  }

  return (
    <div className="add-zone-form-panel slide-in">
      {/* Header */}
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:16 }}>
        <div style={{ fontSize:15, fontWeight:800 }}>
          {pendingPin ? '📍 New Zone (dropped pin)' : '+ Add Safe Zone'}
        </div>
        <button onClick={onCancel}
          style={{ background:'none', border:'none', color:'rgba(255,255,255,.4)', cursor:'pointer' }}>
          <X size={16} />
        </button>
      </div>

      {pendingPin && (
        <div style={{
          padding:'8px 12px', borderRadius:8, background:'rgba(232,135,26,.1)',
          border:'1px solid rgba(232,135,26,.25)', fontSize:12, color:'var(--saffron)',
          marginBottom:12,
        }}>
          📍 Pin dropped at {pendingPin.x.toFixed(1)}%, {pendingPin.y.toFixed(1)}%
        </div>
      )}

      {/* Search address */}
      <div className="form-section-label">Address / Search</div>
      <div style={{ position:'relative', marginBottom:0 }}>
        <Search size={13} style={{ position:'absolute', left:10, top:'50%', transform:'translateY(-50%)', color:'rgba(255,255,255,.3)' }} />
        <input className="dark-input" style={{ paddingLeft:32 }}
          placeholder="Search location or click map to drop pin…"
          value={address} onChange={e => setAddress(e.target.value)} />
      </div>

      {/* Zone name */}
      <div className="form-section-label">Zone Name</div>
      <input className="dark-input" placeholder="e.g. Home, Office, Hospital"
        value={name} onChange={e => setName(e.target.value)} />

      {/* Radius slider */}
      <div className="form-section-label" style={{ display:'flex', justifyContent:'space-between' }}>
        <span>Radius</span>
        <span style={{ color:'var(--saffron)', fontWeight:800 }}>{radiusMeters}m</span>
      </div>
      <input type="range" className="dark-slider"
        min={33} max={667} value={radius}
        onChange={e => setRadius(+e.target.value)} />
      <div style={{ display:'flex', justifyContent:'space-between', fontSize:10, color:'rgba(255,255,255,.3)', marginTop:4 }}>
        <span>50m</span><span>500m</span><span>1km</span>
      </div>

      {/* Color */}
      <div className="form-section-label">Color</div>
      <div className="color-picker-row">
        {ZONE_COLORS.map(c => (
          <div key={c} className={`color-swatch-dark ${color === c ? 'selected' : ''}`}
            style={{ background: c }} onClick={() => setColor(c)} />
        ))}
      </div>

      {/* Alert trigger */}
      <div className="form-section-label">Alert Trigger</div>
      <select className="dark-input" value={alertT} onChange={e => setAlertT(e.target.value)}>
        {ZONE_ALERTS.map(a => <option key={a} value={a}>{a}</option>)}
      </select>

      {/* Actions */}
      <div className="zone-form-actions">
        <button className="btn-dark-submit" onClick={handleSave} disabled={!name.trim()}
          style={{ opacity: name.trim() ? 1 : .5 }}>
          ✓ Save Zone
        </button>
        <button className="btn-dark-cancel" onClick={onCancel}>Cancel</button>
      </div>
    </div>
  )
}

// ── Safe Zones Page ──────────────────────────────────────────────
export default function SafeZones() {
  const [activeUser,  setActiveUser]  = useState(DEFAULT_USER)
  const [zones,       setZones]       = useState(INITIAL_ZONES)
  const [selected,    setSelected]    = useState(null)
  const [showForm,    setShowForm]    = useState(false)
  const [pendingPin,  setPendingPin]  = useState(null)
  const [outsideTime, setOutsideTime] = useState('10 min')
  const mapRef = useRef()

  const handleMapClick = (e) => {
    if (!mapRef.current || showForm) return
    const rect = mapRef.current.getBoundingClientRect()
    const x = ((e.clientX - rect.left) / rect.width) * 100
    const y = ((e.clientY - rect.top)  / rect.height) * 100
    setPendingPin({ x, y })
    setShowForm(true)
    setSelected(null)
  }

  const handleSave = ({ name, address, radius, color, alertT }) => {
    const emoji = color === '#16A34A' ? '🏠' : color === '#2563EB' ? '🏫'
                : color === '#7C3AED' ? '🛒' : color === '#E8871A' ? '🏪'
                : color === '#DC2626' ? '🏥' : '📍'
    const position = pendingPin || { x: 50, y: 50 }
    setZones(prev => [...prev, {
      id: Date.now(), name, address, radius, color,
      alert: alertT, emoji,
      x: position.x, y: position.y,
    }])
    setShowForm(false)
    setPendingPin(null)
  }

  const handleDelete = (id) => {
    setZones(prev => prev.filter(z => z.id !== id))
    if (selected === id) setSelected(null)
  }

  return (
    <div className="page-root">
      <Navbar activeUser={activeUser} onUserChange={setActiveUser}
        isSOS={false} onBellClick={() => {}} bellCount={3} />
      <div className="page-body">
        <Sidebar activeUser={activeUser} />

        {/* ── Full split layout ─────────────────────────────── */}
        <div className="zones-layout">

          {/* ── Map column ───────────────────────────────────── */}
          <div className="zones-map-col" ref={mapRef} onClick={handleMapClick}>
            <div className="zones-map-bg" />

            {/* Roads */}
            <div className="zones-road" style={{ left:'22%', top:0, bottom:0, width:7 }} />
            <div className="zones-road" style={{ left:'50%', top:0, bottom:0, width:7 }} />
            <div className="zones-road" style={{ left:'75%', top:0, bottom:0, width:5 }} />
            <div className="zones-road" style={{ top:'28%', left:0, right:0, height:7 }} />
            <div className="zones-road" style={{ top:'55%', left:0, right:0, height:7 }} />
            <div className="zones-road" style={{ top:'75%', left:0, right:0, height:5 }} />

            {/* Zone circles */}
            {zones.map(z => (
              <ZoneCircle key={z.id} zone={z}
                selected={selected === z.id}
                onClick={(e) => {
                  e.stopPropagation()
                  setSelected(selected === z.id ? null : z.id)
                  setShowForm(false)
                }}
              />
            ))}

            {/* Pending pin */}
            {pendingPin && showForm && (
              <div className="drop-pin"
                style={{ left:`${pendingPin.x}%`, top:`${pendingPin.y}%` }}>
                📍
              </div>
            )}

            {/* Selected zone detail bubble */}
            <AnimatePresence>
              {selected && !showForm && (() => {
                const z = zones.find(z => z.id === selected)
                if (!z) return null
                return (
                  <motion.div
                    key={z.id}
                    initial={{ opacity:0, scale:.92 }}
                    animate={{ opacity:1, scale:1 }}
                    exit={{ opacity:0, scale:.92 }}
                    style={{
                      position:'absolute',
                      left: `${Math.min(z.x + 8, 65)}%`,
                      top:  `${Math.max(z.y - 16, 5)}%`,
                      zIndex: 30,
                      background:'rgba(13,27,46,.95)',
                      backdropFilter:'blur(16px)',
                      border:`1px solid ${z.color}55`,
                      borderRadius:14, padding:'14px 16px',
                      minWidth:200,
                      boxShadow:'0 8px 32px rgba(0,0,0,.4)',
                      pointerEvents:'all',
                    }}
                    onClick={e => e.stopPropagation()}>
                    <div style={{ display:'flex', alignItems:'center', gap:8, marginBottom:8 }}>
                      <div style={{ width:10, height:10, borderRadius:'50%', background:z.color, flexShrink:0 }} />
                      <span style={{ fontWeight:800, fontSize:14 }}>{z.name}</span>
                      <button onClick={() => setSelected(null)}
                        style={{ marginLeft:'auto', background:'none', border:'none',
                          color:'rgba(255,255,255,.4)', cursor:'pointer' }}>
                        <X size={13} />
                      </button>
                    </div>
                    <div style={{ fontSize:12, color:'rgba(255,255,255,.5)', marginBottom:4 }}>📍 {z.address}</div>
                    <div style={{ fontSize:12, color:'rgba(255,255,255,.5)', marginBottom:4 }}>⬤ ~{Math.round(z.radius * 1.5)}m radius</div>
                    <div style={{ fontSize:12, color:'rgba(255,255,255,.5)' }}>🔔 Alert on: {z.alert}</div>
                  </motion.div>
                )
              })()}
            </AnimatePresence>

            {/* Map header search */}
            <div className="zones-map-header" onClick={e => e.stopPropagation()}>
              <div style={{ position:'relative', flex:1 }}>
                <Search size={13} className="zones-map-search-icon" />
                <input className="zones-map-search"
                  placeholder="Search address to add a zone…"
                  onClick={e => e.stopPropagation()} />
              </div>
            </div>

            {/* Tip */}
            {!showForm && (
              <div className="zones-map-tip">👆 Click the map to drop a pin and add a zone</div>
            )}
          </div>

          {/* ── Right panel ───────────────────────────────────── */}
          <div className="zones-right-col">
            <div className="zones-panel-header">
              <span className="zones-panel-title">Safe Zones ({zones.length})</span>
              <button className="add-zone-btn" onClick={() => { setShowForm(true); setPendingPin(null) }}>
                <Plus size={14} /> Add Zone
              </button>
            </div>

            {/* Zone list OR add form */}
            <div style={{ flex:1, position:'relative', overflow:'hidden' }}>
              <div className="zones-list">
                <AnimatePresence initial={false}>
                  {zones.map((z, i) => (
                    <motion.div key={z.id}
                      initial={{ opacity:0, y:-10 }}
                      animate={{ opacity:1, y:0 }}
                      exit={{ opacity:0, x:20, height:0, marginBottom:0, padding:0 }}
                      transition={{ duration:.25 }}>
                      <div
                        className={`zone-card ${selected === z.id ? 'selected' : ''}`}
                        onClick={() => { setSelected(selected === z.id ? null : z.id); setShowForm(false) }}>
                        <div className="zone-card-top">
                          <div className="zone-card-dot" style={{ background: z.color }} />
                          <div className="zone-card-name">{z.emoji} {z.name}</div>
                        </div>
                        <div className="zone-card-body">
                          <span>📍 {z.address}</span>
                          <span>⬤ ~{Math.round(z.radius * 1.5)}m radius</span>
                          <span>🔔 Alert when: {z.alert}</span>
                        </div>
                        <div className="zone-card-actions" onClick={e => e.stopPropagation()}>
                          <button className="zone-action-btn"
                            onClick={() => { setSelected(z.id); setShowForm(true); setPendingPin({ x:z.x, y:z.y }) }}>
                            <Edit2 size={11} /> Edit
                          </button>
                          <button className="zone-action-btn danger"
                            onClick={() => handleDelete(z.id)}>
                            <Trash2 size={11} /> Delete
                          </button>
                        </div>
                      </div>
                    </motion.div>
                  ))}
                </AnimatePresence>
              </div>

              {/* Add form overlay */}
              <AnimatePresence>
                {showForm && (
                  <motion.div style={{ position:'absolute', inset:0 }}
                    initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }}
                    transition={{ duration:.2 }}>
                    <AddZoneForm
                      pendingPin={pendingPin}
                      onSave={handleSave}
                      onCancel={() => { setShowForm(false); setPendingPin(null) }}
                    />
                  </motion.div>
                )}
              </AnimatePresence>
            </div>

            {/* Footer — outside all zones alert */}
            <div className="zones-footer">
              <div style={{ fontSize:11, fontWeight:700, color:'rgba(255,255,255,.35)',
                letterSpacing:.5, marginBottom:8, textTransform:'uppercase' }}>
                Outside All Zones Alert
              </div>
              <div className="zones-footer-row">
                <span>🔔 Alert me if Arjun is outside ALL safe zones for more than</span>
                <select className="zones-footer-select"
                  value={outsideTime} onChange={e => setOutsideTime(e.target.value)}>
                  {OUTSIDE_TIMES.map(t => <option key={t} value={t}>{t}</option>)}
                </select>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
