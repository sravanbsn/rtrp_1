// src/pages/RouteHistory.jsx — Route history from Firestore
import { useState, useEffect } from 'react'
import { collection, query, where, orderBy, limit, onSnapshot } from 'firebase/firestore'
import { format } from 'date-fns'
import { motion } from 'framer-motion'
import { MapPin, Clock, TrendingUp, Shield, ChevronDown, ChevronUp } from 'lucide-react'
import Navbar  from '../components/Navbar'
import Sidebar from '../components/Sidebar'
import { db } from '../config/firebase'
import { useAuth } from '../contexts/AuthContext'
import '../dashboard.css'
import '../pages.css'

const DEFAULT_USER = { id: 1, initials: 'AR', name: 'Arjun Sharma', status: 'Online', color: '#E8871A' }

function safetyColor(score) {
  if (score >= 80) return '#10B981'
  if (score >= 60) return '#F59E0B'
  return '#EF4444'
}

function safetyLabel(score) {
  if (score >= 80) return 'Safe'
  if (score >= 60) return 'Fair'
  return 'Risky'
}

// ── Route Card ─────────────────────────────────────────────────────
function RouteCard({ route, index }) {
  const [expanded, setExpanded] = useState(false)
  const color = safetyColor(route.safetyScore)

  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.05 }}
      style={{
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(255,255,255,0.08)',
        borderRadius: 12,
        marginBottom: 12,
        overflow: 'hidden',
      }}
    >
      {/* Main row */}
      <div
        onClick={() => setExpanded(v => !v)}
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr 100px 80px 80px 80px 40px',
          gap: 12, alignItems: 'center',
          padding: '14px 20px', cursor: 'pointer',
        }}
      >
        {/* Route info */}
        <div>
          <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 4 }}>
            {route.from} → {route.to}
          </div>
          <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.4)', display: 'flex', gap: 12 }}>
            <span><Clock size={11} style={{ marginRight: 3 }} />{route.date}</span>
            <span><MapPin size={11} style={{ marginRight: 3 }} />{route.distance}</span>
          </div>
        </div>

        {/* Duration */}
        <div style={{ fontSize: 13, color: 'rgba(255,255,255,0.6)', textAlign: 'center' }}>
          {route.duration}
        </div>

        {/* Overrides */}
        <div style={{ textAlign: 'center' }}>
          <span style={{
            background: route.overrides > 0 ? 'rgba(239,68,68,0.15)' : 'rgba(16,185,129,0.15)',
            color:       route.overrides > 0 ? '#EF4444' : '#10B981',
            padding: '2px 10px', borderRadius: 20, fontSize: 12, fontWeight: 700,
          }}>
            {route.overrides} stop{route.overrides !== 1 ? 's' : ''}
          </span>
        </div>

        {/* Hazards */}
        <div style={{ textAlign: 'center', fontSize: 13, color: 'rgba(255,255,255,0.6)' }}>
          ⚠️ {route.hazards}
        </div>

        {/* Safety score */}
        <div style={{ textAlign: 'center' }}>
          <span style={{
            background: color + '22', color, padding: '2px 10px',
            borderRadius: 20, fontSize: 12, fontWeight: 800,
          }}>
            {route.safetyScore}% {safetyLabel(route.safetyScore)}
          </span>
        </div>

        {/* Expand */}
        <div style={{ color: 'rgba(255,255,255,0.3)' }}>
          {expanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
        </div>
      </div>

      {/* Expanded detail */}
      {expanded && (
        <div style={{
          borderTop: '1px solid rgba(255,255,255,0.06)',
          padding: '16px 20px',
          display: 'grid', gridTemplateColumns: '1fr 1fr',
          gap: 20,
        }}>
          {/* Route map placeholder */}
          <div style={{
            background: 'rgba(255,255,255,0.03)',
            border: '1px solid rgba(255,255,255,0.06)',
            borderRadius: 10, padding: 16,
            minHeight: 120,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexDirection: 'column', gap: 8,
            color: 'rgba(255,255,255,0.3)', fontSize: 13,
          }}>
            <MapPin size={24} />
            <span>Route map</span>
            <span style={{ fontSize: 11 }}>{route.from} → {route.to}</span>
          </div>

          {/* Stats */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {[
              { label: 'Started', value: route.startTime },
              { label: 'Ended',   value: route.endTime },
              { label: 'Avg Speed', value: route.avgSpeed || '—' },
              { label: 'AI Overrides', value: `${route.overrides} times` },
              { label: 'Hazards Logged', value: `${route.hazards} events` },
              { label: 'Safety Score', value: `${route.safetyScore}/100` },
            ].map(stat => (
              <div key={stat.label} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}>
                <span style={{ color: 'rgba(255,255,255,0.4)' }}>{stat.label}</span>
                <span style={{ fontWeight: 600 }}>{stat.value}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </motion.div>
  )
}

// ── Format Firestore session to route shape ─────────────────────────
function formatSession(doc) {
  const d    = doc.data()
  const ts   = d.started_at?.toDate ? d.started_at.toDate() : new Date()
  const endTs = d.ended_at?.toDate  ? d.ended_at.toDate()   : null
  const dur  = endTs ? Math.round((endTs - ts) / 60000) : null

  const summary = d.summary || {}
  const overrides = summary.overrides_count || 0
  const hazards   = summary.alerts_count    || 0
  const distance  = summary.distance_m ? `${(summary.distance_m / 1000).toFixed(1)}km` : '—'

  // Safety score: 100 - penalties
  const safetyScore = Math.max(0, Math.round(100 - (overrides * 10) - (hazards * 2)))

  return {
    id:          doc.id,
    from:        d.start_location_label || 'Start',
    to:          d.end_location_label   || 'End',
    date:        format(ts, 'MMM dd, yyyy'),
    startTime:   format(ts, 'h:mm a'),
    endTime:     endTs ? format(endTs, 'h:mm a') : 'Ongoing',
    duration:    dur ? `${dur} min` : '—',
    distance,
    overrides,
    hazards,
    safetyScore,
    avgSpeed:    summary.avg_speed_mps ? `${(summary.avg_speed_mps * 3.6).toFixed(1)} km/h` : '—',
  }
}

// ── Route History Page ──────────────────────────────────────────────
export default function RouteHistory() {
  const { guardianProfile } = useAuth()
  const [activeUser, setActiveUser] = useState(DEFAULT_USER)
  const [routes,     setRoutes]     = useState([])
  const [loading,    setLoading]    = useState(true)

  useEffect(() => {
    const uid = guardianProfile?.linked_user_uid
    if (!uid) { setLoading(false); return }

    const q = query(
      collection(db, 'sessions'),
      where('user_id', '==', uid),
      orderBy('started_at', 'desc'),
      limit(50)
    )

    const unsub = onSnapshot(q, (snap) => {
      setRoutes(snap.docs.map(formatSession))
      setLoading(false)
    }, () => setLoading(false))

    return () => unsub()
  }, [guardianProfile?.linked_user_uid])

  // Summary stats
  const totalDist  = routes.reduce((s, r) => s + (parseFloat(r.distance) || 0), 0).toFixed(1)
  const avgSafety  = routes.length ? Math.round(routes.reduce((s,r) => s + r.safetyScore, 0) / routes.length) : 0
  const totalOvr   = routes.reduce((s, r) => s + r.overrides, 0)

  return (
    <div className="page-root">
      <Navbar activeUser={activeUser} onUserChange={setActiveUser} isSOS={false} onBellClick={() => {}} bellCount={0} />
      <div className="page-body">
        <Sidebar activeUser={activeUser} />
        <div className="page-content">

          <div className="page-header">
            <div>
              <div className="page-title">Route History</div>
              <div className="page-breadcrumb">All navigation sessions · Firestore</div>
            </div>
          </div>

          {/* Summary cards */}
          <div className="stat-cards-row">
            {[
              { label: 'Total Routes',    value: String(routes.length), cls: 'saffron', sub: 'Sessions logged', icon: <MapPin size={14} /> },
              { label: 'Total Distance',  value: `${totalDist}km`,      cls: 'blue',    sub: 'Walked safely',   icon: <TrendingUp size={14} /> },
              { label: 'Avg Safety',      value: `${avgSafety}%`,       cls: 'green',   sub: 'Safety score',    icon: <Shield size={14} /> },
              { label: 'Total Stops',     value: String(totalOvr),      cls: 'yellow',  sub: 'AI overrides',    icon: <Clock size={14} /> },
            ].map((s, i) => (
              <motion.div key={s.label} className="stat-card"
                initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.06 }}>
                <div className="stat-card-label">{s.label}</div>
                <div className={`stat-card-value ${s.cls}`}>{s.value}</div>
                <div className="stat-card-sub">{s.sub}</div>
              </motion.div>
            ))}
          </div>

          {/* Table header */}
          <div style={{
            display: 'grid',
            gridTemplateColumns: '1fr 100px 80px 80px 80px 40px',
            gap: 12, padding: '10px 20px',
            fontSize: 11, fontWeight: 700,
            color: 'rgba(255,255,255,0.3)',
            letterSpacing: 0.5, textTransform: 'uppercase',
            borderBottom: '1px solid rgba(255,255,255,0.06)',
            marginBottom: 8,
          }}>
            <span>Route</span><span style={{ textAlign: 'center' }}>Duration</span>
            <span style={{ textAlign: 'center' }}>Stops</span>
            <span style={{ textAlign: 'center' }}>Hazards</span>
            <span style={{ textAlign: 'center' }}>Safety</span>
            <span />
          </div>

          {/* Route list */}
          {loading ? (
            <div style={{ textAlign: 'center', padding: '40px 0', color: 'rgba(255,255,255,0.4)' }}>Loading routes…</div>
          ) : routes.length === 0 ? (
            <div className="alerts-empty">
              <div className="alerts-empty-emoji">🗺️</div>
              <div className="alerts-empty-title">No routes yet</div>
              <div className="alerts-empty-sub">
                {!guardianProfile?.linked_user_uid ? 'Link a user to see their routes.' : 'Arjun hasn\'t taken any walks yet.'}
              </div>
            </div>
          ) : (
            routes.map((r, i) => <RouteCard key={r.id} route={r} index={i} />)
          )}
        </div>
      </div>
    </div>
  )
}
