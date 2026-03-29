import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Phone, MessageSquare, MapPin, AlertOctagon } from 'lucide-react'

// ── Collision arc gauge ──────────────────────────────────────────
function CollisionGauge({ value }) {
  const radius = 36
  const circumference = Math.PI * radius  // semicircle
  const dashOffset = circumference * (1 - value / 100)
  const color = value < 30 ? '#4ADE80' : value < 65 ? '#FBBF24' : '#F87171'
  const cls   = value < 30 ? 'green'   : value < 65 ? 'yellow'  : 'red'

  return (
    <div className="gauge-wrap">
      <svg className="gauge-svg" width="90" height="52" viewBox="0 0 90 52">
        {/* Track */}
        <path d="M 8 46 A 36 36 0 0 1 82 46"
          fill="none" stroke="rgba(255,255,255,.08)" strokeWidth="8" strokeLinecap="round" />
        {/* Fill */}
        <path d="M 8 46 A 36 36 0 0 1 82 46"
          fill="none" stroke={color} strokeWidth="8" strokeLinecap="round"
          strokeDasharray={`${circumference}`}
          strokeDashoffset={`${dashOffset}`}
          style={{ transition:'stroke-dashoffset 1s ease, stroke .6s ease',
            filter:`drop-shadow(0 0 4px ${color}88)` }}
        />
        {/* Value text */}
        <text x="45" y="46" textAnchor="middle"
          fill={color} fontSize="13" fontWeight="900" fontFamily="Inter, sans-serif">
          {value}%
        </text>
      </svg>
      <div className="gauge-info">
        <div className="gauge-label">Collision Risk</div>
        <div className={`gauge-value ${cls}`}>{value}%</div>
        <div className="gauge-sub">
          {value < 30 ? 'All clear' : value < 65 ? 'Caution' : 'High risk'}
        </div>
      </div>
    </div>
  )
}

// ── Initial alert stream ─────────────────────────────────────────
const INITIAL_STREAM = [
  { id:1, time:'2:41 PM', icon:'🔴', text:'Arjun was stopped — vehicle 8m away', type:'danger' },
  { id:2, time:'2:38 PM', icon:'🟡', text:'Pothole detected — rerouted left',     type:'warning' },
  { id:3, time:'2:30 PM', icon:'🟢', text:'Navigation started — Ghar to Market',  type:'safe' },
  { id:4, time:'2:25 PM', icon:'🟢', text:'Connected — Drishti AI active',         type:'safe' },
]

const QUICK_ACTIONS = [
  { icon: <Phone size={14} />,          label: 'Call Arjun',       type: 'normal' },
  { icon: <MessageSquare size={14} />,  label: 'Voice Note',       type: 'normal' },
  { icon: <MapPin size={14} />,         label: 'Location',         type: 'normal' },
  { icon: <AlertOctagon size={14} />,   label: 'Trigger SOS',      type: 'sos' },
]

export default function LiveFeed({ riskValue, onSOS }) {
  const [stream, setStream] = useState(INITIAL_STREAM)
  const [nextId, setNextId] = useState(10)

  // Simulate occasional new alerts sliding in
  useEffect(() => {
    const LIVE_ALERTS = [
      { icon:'🟡', text:'Uneven pavement ahead — reducing speed', type:'warning' },
      { icon:'🟢', text:'Clear path — continuing route',          type:'safe'    },
      { icon:'🔴', text:'Pedestrian conflict — brief stop',       type:'danger'  },
      { icon:'🟡', text:'High crowd density area — rerouting',    type:'warning' },
    ]
    let i = 0
    const iv = setInterval(() => {
      const now = new Date()
      const time = now.toLocaleTimeString('en-IN', { hour:'2-digit', minute:'2-digit' })
      const alert = LIVE_ALERTS[i % LIVE_ALERTS.length]
      setStream(prev => [{ id: Date.now(), time, ...alert }, ...prev.slice(0, 14)])
      setNextId(n => n+1)
      i++
    }, 7000)
    return () => clearInterval(iv)
  }, [])

  const now = new Date()
  const timeStr = now.toLocaleTimeString('en-IN', { hour:'2-digit', minute:'2-digit' })

  return (
    <div className="dash-feed-col">
      {/* ── User status card ──────────────────────────────────── */}
      <div className="feed-status-card">
        <div className="feed-user-row">
          <div className="feed-user-photo">AR</div>
          <div className="feed-user-info">
            <div className="feed-user-name">Arjun Sharma</div>
            <div className="feed-user-status">Walking — 1.2 km covered</div>
          </div>
        </div>

        {/* Meta chips */}
        <div className="feed-meta-row">
          <div className="feed-meta-chip">🔋 78%</div>
          <div className="feed-meta-chip green">📡 GPS Strong</div>
          <div className="feed-meta-chip saffron">🤖 AI Active</div>
        </div>

        {/* Collision gauge */}
        <CollisionGauge value={riskValue} />
      </div>

      {/* ── Stream header ─────────────────────────────────────── */}
      <div className="feed-stream-header">
        <span className="feed-stream-title">LIVE ALERTS</span>
        <div className="live-badge">
          <div className="live-dot" /> LIVE
        </div>
      </div>

      {/* ── Alert stream ──────────────────────────────────────── */}
      <div className="feed-stream">
        <AnimatePresence initial={false}>
          {stream.map((entry) => (
            <motion.div key={entry.id}
              className={`stream-entry ${entry.type}`}
              initial={{ opacity:0, y:-16, scale:.98 }}
              animate={{ opacity:1, y:0, scale:1 }}
              transition={{ duration:.3, ease:'easeOut' }}>
              <div className="stream-time">{entry.time}</div>
              <div className="stream-icon">{entry.icon}</div>
              <div className="stream-text">{entry.text}</div>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>

      {/* ── Quick actions ─────────────────────────────────────── */}
      <div className="feed-actions">
        {QUICK_ACTIONS.map(a => (
          <button key={a.label}
            className={`action-btn ${a.type === 'sos' ? 'sos-btn' : ''}`}
            onClick={a.type === 'sos' ? onSOS : undefined}>
            {a.icon}
            {a.label}
          </button>
        ))}
      </div>
    </div>
  )
}
