import { useState, useEffect, useRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { ZoomIn, ZoomOut, Layers, Box } from 'lucide-react'
import AlertPopup from './AlertPopup'

// ── Hazard data ───────────────────────────────────────────────────
const HAZARDS = [
  { id: 1, type: 'danger',  emoji: '🔴', label: 'Vehicle — 8m',   x: 56, y: 40 },
  { id: 2, type: 'warning', emoji: '🟡', label: 'Pothole',         x: 38, y: 62 },
  { id: 3, type: 'crowd',   emoji: '🟠', label: 'High Density',    x: 70, y: 55 },
]

// ── Summary data ──────────────────────────────────────────────────
const SUMMARY = [
  { label: 'Distance',      value: '2.3km',    cls: 'saffron' },
  { label: 'Alerts Today',  value: '3',        cls: 'yellow' },
  { label: 'Overrides',     value: '1',        cls: 'red' },
  { label: 'Walking Since', value: '2:30 PM',  cls: 'green' },
]

// ── Digital Twin 3D view ──────────────────────────────────────────
function DigitalTwin() {
  return (
    <div className="twin-view">
      <div className="twin-label">⬡ Digital Twin — Isometric View</div>
      <div className="twin-grid">
        <div className="twin-grid-inner" />
      </div>
      {/* rudimentary "buildings" */}
      {[
        { w:60,h:80, left:'30%', top:'30%', color:'#1E3A5F' },
        { w:40,h:50, left:'55%', top:'25%', color:'#162D4A' },
        { w:70,h:60, left:'65%', top:'55%', color:'#1A3455' },
        { w:30,h:40, left:'20%', top:'60%', color:'#112238' },
      ].map((b, i) => (
        <div key={i} style={{
          position:'absolute', left:b.left, top:b.top,
          width:b.w, height:b.h,
          background:b.color,
          border:'1px solid rgba(100,160,255,.2)',
          transform:'rotateX(-12deg) rotateY(6deg) skewX(-2deg)',
        }} />
      ))}
      {/* User walking dot */}
      <div style={{ position:'absolute', left:'47%', top:'45%' }}>
        <div style={{
          width:12, height:12, borderRadius:'50%', background:'#3B82F6',
          boxShadow:'0 0 12px rgba(59,130,246,.8)',
        }} />
      </div>
    </div>
  )
}

// ── Main Map Canvas ───────────────────────────────────────────────
function MapCanvas({ showPopup, onDismissPopup }) {
  const [userPos, setUserPos] = useState({ x: 48, y: 48 })
  const pathRef = useRef([{ x: 28, y: 72 }, { x: 35, y: 64 }, { x: 42, y: 57 }, { x: 48, y: 48 }])

  // Slowly move user along a path
  useEffect(() => {
    const iv = setInterval(() => {
      setUserPos(prev => {
        const nx = Math.min(72, prev.x + (Math.random() - 0.3) * 0.4)
        const ny = Math.max(28, prev.y + (Math.random() - 0.7) * 0.4)
        pathRef.current.push({ x: nx, y: ny })
        if (pathRef.current.length > 60) pathRef.current.shift()
        return { x: nx, y: ny }
      })
    }, 800)
    return () => clearInterval(iv)
  }, [])

  const pathPoints = pathRef.current
    .map(p => `${p.x}% ${p.y}%`)
    .join(', ')

  return (
    <div className="map-canvas">
      {/* Roads */}
      <div className="map-road" style={{ left:'20%', top:0, bottom:0, width:6 }} />
      <div className="map-road" style={{ left:'50%', top:0, bottom:0, width:6 }} />
      <div className="map-road" style={{ left:'75%', top:0, bottom:0, width:4 }} />
      <div className="map-road" style={{ top:'30%', left:0, right:0, height:6 }} />
      <div className="map-road" style={{ top:'60%', left:0, right:0, height:6 }} />

      {/* Safe zone */}
      <div className="map-safe-zone" style={{
        left:'15%', top:'50%', width:220, height:220,
        marginLeft:-110, marginTop:-110,
      }} />
      <div style={{
        position:'absolute', left:'15%', top:'calc(50% + 118px)',
        transform:'translateX(-50%)',
        fontSize:10, fontWeight:700, color:'rgba(22,163,74,.7)',
        whiteSpace:'nowrap',
      }}>🟢 Ghar Safe Zone</div>

      {/* Crowd density shading */}
      <div style={{
        position:'absolute', left:'60%', top:'46%',
        width:110, height:90, borderRadius:'50%',
        background:'rgba(249,115,22,.08)',
        border:'1.5px solid rgba(249,115,22,.25)',
        transform:'translate(-50%,-50%)',
      }} />
      <div style={{
        position:'absolute', left:'70%', top: 'calc(46% + 48px)',
        transform:'translateX(-50%)',
        fontSize:10, fontWeight:600, color:'rgba(249,115,22,.7)',
      }}>High Density</div>

      {/* Walked path — use SVG viewBox so percentages become proportional numbers */}
      <svg className="map-path"
        style={{ position:'absolute', inset:0, width:'100%', height:'100%' }}
        viewBox="0 0 100 100" preserveAspectRatio="none">
        <polyline
          points={pathRef.current.map(p => `${p.x},${p.y}`).join(' ')}
          fill="none" stroke="rgba(59,130,246,.55)" strokeWidth="0.6"
          strokeLinecap="round" strokeLinejoin="round"
          strokeDasharray="1.5,0.8"
          vectorEffect="non-scaling-stroke"
        />
      </svg>

      {/* Hazard pins */}
      {HAZARDS.filter(h => h.type !== 'crowd').map(h => (
        <div key={h.id} className="map-pin" style={{ left:`${h.x}%`, top:`${h.y}%` }}>
          <div className="map-pin-bubble">{h.label}</div>
          <div style={{ textAlign:'center', fontSize:22, lineHeight:1 }}>{h.emoji}</div>
        </div>
      ))}

      {/* User dot */}
      <div className="map-user-dot" style={{ left:`${userPos.x}%`, top:`${userPos.y}%` }}>
        <div className="map-dot-ring" />
        <div className="map-dot-ring map-dot-ring2" />
        <div className="map-dot-ring map-dot-ring3" />
        <div className="map-dot-core" />
      </div>

      {/* Controls */}
      <div className="map-controls-panel">
        <button className="map-ctrl-btn" title="Zoom in"><ZoomIn size={15} /></button>
        <button className="map-ctrl-btn" title="Zoom out"><ZoomOut size={15} /></button>
        <button className="map-ctrl-btn" title="Satellite">🛰</button>
        <button className="map-ctrl-btn" title="3D view"><Box size={15} /></button>
      </div>

      {/* Alert popup */}
      <AnimatePresence>
        {showPopup && (
          <motion.div className="alert-popup-wrap"
            initial={{ y: -80, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: -80, opacity: 0 }}
            transition={{ type:'spring', damping:20 }}>
            <AlertPopup onDismiss={onDismissPopup} />
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}

// ── MapPanel (map + twin toggle + summary strip) ──────────────────
export default function MapPanel({ showPopup, onDismissPopup }) {
  const [twinMode, setTwinMode] = useState(false)

  return (
    <div className="dash-map-col">
      <div className="dash-map-wrap">
        {twinMode ? <DigitalTwin /> : <MapCanvas showPopup={showPopup} onDismissPopup={onDismissPopup} />}

        {/* Digital twin toggle */}
        <button className={`twin-toggle ${twinMode ? 'active' : ''}`}
          onClick={() => setTwinMode(v => !v)}>
          <div className="twin-toggle-dot" />
          {twinMode ? 'Live Map' : 'Digital Twin'}
        </button>
      </div>

      {/* Summary strip */}
      <div className="dash-summary-strip">
        {SUMMARY.map(s => (
          <div key={s.label} className="summary-stat">
            <div>
              <div className="summary-stat-label">{s.label}</div>
              <div className={`summary-stat-value ${s.cls}`}>{s.value}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
