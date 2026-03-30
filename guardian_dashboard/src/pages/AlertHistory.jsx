// src/pages/AlertHistory.jsx — Alert History with real Firestore data
import { useState, useMemo, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { collection, query, where, orderBy, onSnapshot } from 'firebase/firestore'
import { format, subDays, startOfDay, isAfter } from 'date-fns'
import { FileDown, MapPin, ChevronDown, ChevronUp, Search, RefreshCw } from 'lucide-react'
import Navbar  from '../components/Navbar'
import Sidebar from '../components/Sidebar'
import { db } from '../config/firebase'
import { useAuth } from '../contexts/AuthContext'
import '../dashboard.css'
import '../pages.css'

const TYPE_FILTERS = ['All', 'Override', 'Warning', 'Clear', 'SOS']

const TYPE_BADGE = {
  override: <span className="alert-type-badge badge-override">🔴 Override</span>,
  warning:  <span className="alert-type-badge badge-warning">🟡 Warning</span>,
  clear:    <span className="alert-type-badge badge-clear">🟢 Clear</span>,
  sos:      <span className="alert-type-badge badge-sos">🆘 SOS</span>,
}

const MAP_COLOR = { override: '#F87171', warning: '#FCD34D', clear: '#4ADE80', sos: '#FCA5A5' }

const DEFAULT_USER = { id: 1, initials: 'AR', name: 'Arjun Sharma', status: 'Navigating', color: '#E8871A' }

// ── Format Firestore alert to display shape ────────────────────────
function formatAlert(doc) {
  const d = doc.data ? doc.data() : doc
  const ts = d.created_at?.toDate ? d.created_at.toDate() : new Date()
  const type = (d.alert_type || d.type || 'clear').toLowerCase().replace('_triggered', '')
  return {
    id:        doc.id || d.id,
    date:      format(ts, 'MMM dd'),
    time:      format(ts, 'h:mm a'),
    type,
    typeLabel: type.charAt(0).toUpperCase() + type.slice(1),
    desc:      d.body || d.description || d.title || 'Navigation event',
    location:  d.location_label || `${(d.location_lat||0).toFixed(4)}, ${(d.location_lng||0).toFixed(4)}`,
    duration:  d.duration || '—',
    prob:      Math.round((d.pc_score || 0) * 100),
    ai:        d.ai_explanation || d.body || 'No AI report available.',
    notified:  !!d.guardian_notified,
    response:  d.user_response || 'Auto-resolved',
    mapColor:  MAP_COLOR[type] || '#94A3B8',
    rawTs:     ts,
  }
}

// ── Date filter helper ─────────────────────────────────────────────
function getDateThreshold(filter) {
  const now = new Date()
  if (filter === 'today')      return startOfDay(now)
  if (filter === 'this-week')  return subDays(now, 7)
  if (filter === 'this-month') return subDays(now, 30)
  return new Date(0) // all-time
}

// ── Expandable row ─────────────────────────────────────────────────
function AlertRow({ alert, index }) {
  const [expanded, setExpanded] = useState(false)
  return (
    <div className={`alert-row ${expanded ? 'expanded' : ''}`} style={{ animationDelay: `${index * 40}ms` }}>
      <div className="alert-row-main" onClick={() => setExpanded(v => !v)}>
        <div className="alert-col-date">{alert.date}</div>
        <div className="alert-col-time">{alert.time}</div>
        <div className="alert-col-type">{TYPE_BADGE[alert.type] || TYPE_BADGE.clear}</div>
        <div className="alert-col-desc">{alert.desc}</div>
        <div className="alert-col-loc">
          <MapPin size={11} style={{ display: 'inline', marginRight: 3 }} />
          {alert.location}
        </div>
        <div className="alert-col-dur">{alert.duration}</div>
        <div className="alert-col-link" onClick={e => e.stopPropagation()}>
          📍 View
          {expanded ? <ChevronUp size={13} style={{ marginLeft: 'auto' }} /> : <ChevronDown size={13} style={{ marginLeft: 'auto' }} />}
        </div>
      </div>
      <AnimatePresence initial={false}>
        {expanded && (
          <motion.div className="alert-row-detail slide-in"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: .25 }}
            style={{ overflow: 'hidden' }}>
            <div className="alert-detail-grid">
              <div className="alert-mini-map">
                <div className="alert-mini-map-grid" />
                <div style={{ position: 'absolute', left: '50%', top: 0, bottom: 0, width: 5, background: 'rgba(255,255,255,.06)' }} />
                <div style={{ position: 'absolute', top: '50%', left: 0, right: 0, height: 5, background: 'rgba(255,255,255,.06)' }} />
                <div className="alert-mini-ring" style={{ width: 50, height: 50, top: '50%', left: '50%', marginTop: -25, marginLeft: -25 }} />
                <div className="alert-mini-ring" style={{ width: 80, height: 80, top: '50%', left: '50%', marginTop: -40, marginLeft: -40, animationDelay: '.6s' }} />
                <div className="alert-mini-pin" style={{ color: alert.mapColor }}>📍</div>
                <div style={{ position: 'absolute', bottom: 8, right: 10, fontSize: 10, color: 'rgba(255,255,255,.35)', fontWeight: 600 }}>{alert.location}</div>
              </div>
              <div className="alert-ai-detail">
                <div className="alert-ai-title">🤖 Drishti AI Report</div>
                <div>{alert.ai}</div>
                <div className="alert-meta-chips">
                  <div className={`alert-meta-chip ${alert.notified ? 'yes' : ''}`}>
                    {alert.notified ? '✓ Guardian notified' : '— Not notified'}
                  </div>
                  <div className="alert-meta-chip">👤 {alert.response}</div>
                  <div className="alert-meta-chip">⚡ {alert.prob}% risk</div>
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}

// ── Alert History Page ─────────────────────────────────────────────
export default function AlertHistory() {
  const { guardianProfile } = useAuth()
  const [activeUser,  setActiveUser]  = useState(DEFAULT_USER)
  const [alerts,      setAlerts]      = useState([])
  const [loading,     setLoading]     = useState(true)
  const [typeFilter,  setTypeFilter]  = useState('All')
  const [dateFilter,  setDateFilter]  = useState('this-week')
  const [search,      setSearch]      = useState('')

  // ── Live Firestore listener ──────────────────────────────────────
  useEffect(() => {
    const uid = guardianProfile?.linked_user_uid
    if (!uid) { setLoading(false); return }

    const q = query(
      collection(db, 'alerts'),
      where('user_id', '==', uid),
      orderBy('created_at', 'desc')
    )

    const unsub = onSnapshot(q, (snap) => {
      setAlerts(snap.docs.map(d => formatAlert({ id: d.id, data: () => d.data() })))
      setLoading(false)
    }, () => setLoading(false))

    return () => unsub()
  }, [guardianProfile?.linked_user_uid])

  // ── Derived stats ────────────────────────────────────────────────
  const stats = useMemo(() => {
    const threshold = getDateThreshold('this-week')
    const weekAlerts = alerts.filter(a => isAfter(a.rawTs, threshold))
    return [
      { label: 'Total Alerts',    value: String(weekAlerts.length),                          cls: 'saffron', sub: 'This week' },
      { label: 'Overrides',       value: String(weekAlerts.filter(a=>a.type==='override').length), cls: 'yellow',  sub: 'AI stopped user' },
      { label: 'SOS Triggered',   value: String(weekAlerts.filter(a=>a.type==='sos').length),cls: 'green',   sub: weekAlerts.filter(a=>a.type==='sos').length===0?'No emergencies':'Check history' },
      { label: 'Hazards Avoided', value: String(alerts.filter(a=>['override','warning'].includes(a.type)).length), cls: 'blue', sub: 'Since account start' },
    ]
  }, [alerts])

  // ── Client-side filter ───────────────────────────────────────────
  const filtered = useMemo(() => {
    const threshold = getDateThreshold(dateFilter)
    return alerts.filter(a => {
      if (!isAfter(a.rawTs, threshold))                                           return false
      if (typeFilter !== 'All' && a.typeLabel !== typeFilter)                     return false
      if (search && !a.desc.toLowerCase().includes(search.toLowerCase())
                 && !a.location.toLowerCase().includes(search.toLowerCase()))     return false
      return true
    })
  }, [alerts, typeFilter, dateFilter, search])

  return (
    <div className="page-root">
      <Navbar activeUser={activeUser} onUserChange={setActiveUser} isSOS={false} onBellClick={() => {}} bellCount={0} />
      <div className="page-body">
        <Sidebar activeUser={activeUser} />
        <div className="page-content">

          <div className="page-header">
            <div>
              <div className="page-title">Alert History</div>
              <div className="page-breadcrumb">
                {guardianProfile?.linked_user_uid ? 'Real-time · Firestore' : 'No user linked'}
              </div>
            </div>
          </div>

          {/* Stat cards */}
          <div className="stat-cards-row">
            {stats.map((s, i) => (
              <motion.div key={s.label} className="stat-card"
                initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * .06 }}>
                <div className="stat-card-label">{s.label}</div>
                <div className={`stat-card-value ${s.cls}`}>{s.value}</div>
                <div className="stat-card-sub">{s.sub}</div>
              </motion.div>
            ))}
          </div>

          {/* Filter bar */}
          <div className="filter-bar">
            <select className="filter-input" value={dateFilter} onChange={e => setDateFilter(e.target.value)}>
              <option value="today">Today</option>
              <option value="this-week">This Week</option>
              <option value="this-month">This Month</option>
              <option value="all-time">All Time</option>
            </select>
            <div style={{ position: 'relative' }}>
              <Search size={13} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'rgba(255,255,255,.3)' }} />
              <input className="filter-input" placeholder="Search alerts…"
                style={{ paddingLeft: 32, width: 200 }}
                value={search} onChange={e => setSearch(e.target.value)} />
            </div>
            <div className="filter-chip-group">
              {TYPE_FILTERS.map(f => (
                <button key={f} className={`filter-chip ${typeFilter === f ? 'active' : ''}`} onClick={() => setTypeFilter(f)}>{f}</button>
              ))}
            </div>
            <div className="filter-spacer" />
            <button className="export-btn"><FileDown size={14} /> Download PDF</button>
          </div>

          {/* Table header */}
          <div className="alert-table-header">
            <span>Date</span><span>Time</span><span>Type</span>
            <span>Description</span><span>Location</span>
            <span>Duration</span><span>Map</span>
          </div>

          {/* List */}
          <div className="alerts-list">
            {loading ? (
              <div style={{ textAlign: 'center', padding: '40px 0', color: 'rgba(255,255,255,0.4)' }}>
                <RefreshCw size={24} style={{ animation: 'spin 1s linear infinite', marginBottom: 12 }} />
                <div>Loading alerts…</div>
                <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
              </div>
            ) : filtered.length === 0 ? (
              <div className="alerts-empty">
                <div className="alerts-empty-emoji">🎉</div>
                <div className="alerts-empty-title">
                  {!guardianProfile?.linked_user_uid ? 'No user linked yet' : 'No alerts found'}
                </div>
                <div className="alerts-empty-sub">
                  {!guardianProfile?.linked_user_uid
                    ? 'Link a user from Settings to see their alerts here.'
                    : 'Try a different date range or filter.'}
                </div>
              </div>
            ) : (
              filtered.map((alert, i) => <AlertRow key={alert.id} alert={alert} index={i} />)
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
