import { useState, useMemo } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { FileDown, MapPin, ChevronDown, ChevronUp, Search } from 'lucide-react'
import Navbar  from '../components/Navbar'
import Sidebar from '../components/Sidebar'
import '../dashboard.css'
import '../pages.css'

// ── Data ─────────────────────────────────────────────────────────
const ALL_ALERTS = [
  {
    id: 1, date: 'Mar 15', time: '2:41 PM', type: 'override',
    typeLabel: 'Override',
    desc: 'Vehicle came close — Arjun was stopped',
    location: 'Gandhi Nagar Junction', duration: '3 sec',
    prob: 89,
    ai: 'Collision probability was 89%. Moral Governor stopped Arjun immediately. He resumed walking after 3 seconds.',
    notified: true, response: 'Resumed normally',
    mapColor: '#F87171',
  },
  {
    id: 2, date: 'Mar 15', time: '2:38 PM', type: 'warning',
    typeLabel: 'Warning',
    desc: 'Pothole detected — rerouted left',
    location: 'Station Road Footpath', duration: '8 sec',
    prob: 61,
    ai: 'A 12cm deep pothole was detected 4 meters ahead. Drishti rerouted Arjun 1.2m to the left. No contact made.',
    notified: false, response: 'Auto-resolved',
    mapColor: '#FCD34D',
  },
  {
    id: 3, date: 'Mar 15', time: '2:30 PM', type: 'clear',
    typeLabel: 'Clear',
    desc: 'Navigation started — path all clear',
    location: 'Ghar — Banjara Hills', duration: '—',
    prob: 5,
    ai: 'Navigation session started. Initial scan showed no hazards. Drishti confirmed all-clear before proceeding.',
    notified: false, response: 'Auto-resolved',
    mapColor: '#4ADE80',
  },
  {
    id: 4, date: 'Mar 14', time: '5:12 PM', type: 'override',
    typeLabel: 'Override',
    desc: 'Pedestrian conflict at crossing',
    location: 'Subhash Chowk', duration: '5 sec',
    prob: 77,
    ai: '77% collision probability with oncoming pedestrian at 3.5m. Arjun paused for 5 seconds. Pedestrian passed safely.',
    notified: true, response: 'Resumed normally',
    mapColor: '#F87171',
  },
  {
    id: 5, date: 'Mar 14', time: '11:04 AM', type: 'warning',
    typeLabel: 'Warning',
    desc: 'High crowd density — reduced speed',
    location: 'Market — Ameerpet', duration: '45 sec',
    prob: 42,
    ai: 'Crowd density 3.4 people/m² detected. Navigation speed reduced from normal to cautious. No overrides needed.',
    notified: false, response: 'Auto-resolved',
    mapColor: '#FCD34D',
  },
  {
    id: 6, date: 'Mar 13', time: '8:55 AM', type: 'sos',
    typeLabel: 'SOS',
    desc: 'SOS triggered — Guardian notified',
    location: 'Gandhi Nagar Junction', duration: '2 min',
    prob: 95,
    ai: 'Manual SOS triggered by Arjun. Guardian notified within 4 seconds. Arjun confirmed safe after 2 minutes.',
    notified: true, response: 'Guardian called',
    mapColor: '#FCA5A5',
  },
  {
    id: 7, date: 'Mar 13', time: '3:20 PM', type: 'clear',
    typeLabel: 'Clear',
    desc: 'Session ended — reached Market safely',
    location: 'Market — Ameerpet', duration: '—',
    prob: 3,
    ai: 'Navigation session ended successfully. Total distance: 1.8 km. 0 overrides. Destination reached safely.',
    notified: false, response: 'Auto-resolved',
    mapColor: '#4ADE80',
  },
]

const TYPE_FILTERS = ['All', 'Override', 'Warning', 'Clear', 'SOS']

const TYPE_BADGE = {
  override: <span className="alert-type-badge badge-override">🔴 Override</span>,
  warning:  <span className="alert-type-badge badge-warning">🟡 Warning</span>,
  clear:    <span className="alert-type-badge badge-clear">🟢 Clear</span>,
  sos:      <span className="alert-type-badge badge-sos">🆘 SOS</span>,
}

const STATS = [
  { label: 'Total Alerts',      value: '12', cls: 'saffron', sub: 'This week' },
  { label: 'Overrides',         value: '3',  cls: 'yellow',  sub: 'AI stopped Arjun' },
  { label: 'SOS Triggered',     value: '0',  cls: 'green',   sub: 'No emergencies' },
  { label: 'Hazards Avoided',   value: '47', cls: 'blue',    sub: 'Since account start' },
]

const DEFAULT_USER = { id:1, initials:'AR', name:'Arjun Sharma', status:'Navigating', color:'#E8871A' }

// ── Expandable alert row ─────────────────────────────────────────
function AlertRow({ alert, index }) {
  const [expanded, setExpanded] = useState(false)

  return (
    <div className={`alert-row ${expanded ? 'expanded' : ''}`}
      style={{ animationDelay: `${index * 40}ms` }}>
      {/* Main row */}
      <div className="alert-row-main" onClick={() => setExpanded(v => !v)}>
        <div className="alert-col-date">{alert.date}</div>
        <div className="alert-col-time">{alert.time}</div>
        <div className="alert-col-type">{TYPE_BADGE[alert.type]}</div>
        <div className="alert-col-desc">{alert.desc}</div>
        <div className="alert-col-loc">
          <MapPin size={11} style={{ display:'inline', marginRight:3 }} />
          {alert.location}
        </div>
        <div className="alert-col-dur">{alert.duration}</div>
        <div className="alert-col-link" onClick={e => e.stopPropagation()}>
          📍 View
          {expanded
            ? <ChevronUp size={13} style={{ marginLeft:'auto' }} />
            : <ChevronDown size={13} style={{ marginLeft:'auto' }} />}
        </div>
      </div>

      {/* Expanded detail */}
      <AnimatePresence initial={false}>
        {expanded && (
          <motion.div className="alert-row-detail slide-in"
            initial={{ height:0, opacity:0 }}
            animate={{ height:'auto', opacity:1 }}
            exit={{ height:0, opacity:0 }}
            transition={{ duration:.25, ease:'easeInOut' }}
            style={{ overflow:'hidden' }}>
            <div className="alert-detail-grid">
              {/* Mini map */}
              <div className="alert-mini-map">
                <div className="alert-mini-map-grid" />
                {/* Roads */}
                <div style={{ position:'absolute', left:'50%', top:0, bottom:0, width:5, background:'rgba(255,255,255,.06)' }} />
                <div style={{ position:'absolute', top:'50%', left:0, right:0, height:5, background:'rgba(255,255,255,.06)' }} />
                {/* Pin + rings */}
                <div className="alert-mini-ring" style={{ width:50, height:50, top:'50%', left:'50%', marginTop:-25, marginLeft:-25 }} />
                <div className="alert-mini-ring" style={{ width:80, height:80, top:'50%', left:'50%', marginTop:-40, marginLeft:-40, animationDelay:'.6s' }} />
                <div className="alert-mini-pin" style={{ color: alert.mapColor }}>📍</div>
                <div style={{ position:'absolute', bottom:8, right:10, fontSize:10, color:'rgba(255,255,255,.35)', fontWeight:600 }}>
                  {alert.location}
                </div>
              </div>

              {/* AI detail */}
              <div className="alert-ai-detail">
                <div className="alert-ai-title">🤖 Drishti AI Report</div>
                <div>{alert.ai}</div>
                <div className="alert-meta-chips">
                  <div className={`alert-meta-chip ${alert.notified ? 'yes' : ''}`}>
                    {alert.notified ? '✓ Guardian notified' : '— Not notified'}
                  </div>
                  <div className="alert-meta-chip">
                    👤 {alert.response}
                  </div>
                  <div className="alert-meta-chip">
                    ⚡ {alert.prob}% risk
                  </div>
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}

// ── Alert History Page ───────────────────────────────────────────
export default function AlertHistory() {
  const [activeUser, setActiveUser] = useState(DEFAULT_USER)
  const [typeFilter, setTypeFilter] = useState('All')
  const [dateFilter, setDateFilter] = useState('this-week')
  const [search, setSearch] = useState('')

  const filtered = useMemo(() => {
    return ALL_ALERTS.filter(a => {
      if (typeFilter !== 'All' && a.typeLabel !== typeFilter) return false
      if (search && !a.desc.toLowerCase().includes(search.toLowerCase()) &&
          !a.location.toLowerCase().includes(search.toLowerCase())) return false
      return true
    })
  }, [typeFilter, search])

  return (
    <div className="page-root">
      <Navbar activeUser={activeUser} onUserChange={setActiveUser}
        isSOS={false} onBellClick={() => {}} bellCount={3} />
      <div className="page-body">
        <Sidebar activeUser={activeUser} />
        <div className="page-content">

          {/* Header */}
          <div className="page-header">
            <div>
              <div className="page-title">Alert History</div>
              <div className="page-breadcrumb">Arjun Sharma · All recorded events</div>
            </div>
          </div>

          {/* Stat cards */}
          <div className="stat-cards-row">
            {STATS.map(s => (
              <motion.div key={s.label} className="stat-card"
                initial={{ opacity:0, y:12 }} animate={{ opacity:1, y:0 }}
                transition={{ delay: STATS.indexOf(s) * .06 }}>
                <div className="stat-card-label">{s.label}</div>
                <div className={`stat-card-value ${s.cls}`}>{s.value}</div>
                <div className="stat-card-sub">{s.sub}</div>
              </motion.div>
            ))}
          </div>

          {/* Filter bar */}
          <div className="filter-bar">
            {/* Date range */}
            <select className="filter-input" value={dateFilter} onChange={e => setDateFilter(e.target.value)}>
              <option value="today">Today</option>
              <option value="this-week">This Week</option>
              <option value="this-month">This Month</option>
              <option value="all-time">All Time</option>
            </select>

            {/* Search */}
            <div style={{ position:'relative' }}>
              <Search size={13} style={{ position:'absolute', left:10, top:'50%', transform:'translateY(-50%)', color:'rgba(255,255,255,.3)' }} />
              <input className="filter-input" placeholder="Search alerts…"
                style={{ paddingLeft:32, width:200 }}
                value={search} onChange={e => setSearch(e.target.value)} />
            </div>

            {/* Type chips */}
            <div className="filter-chip-group">
              {TYPE_FILTERS.map(f => (
                <button key={f}
                  className={`filter-chip ${typeFilter === f ? 'active' : ''}`}
                  onClick={() => setTypeFilter(f)}>
                  {f}
                </button>
              ))}
            </div>

            <div className="filter-spacer" />

            {/* Export */}
            <button className="export-btn">
              <FileDown size={14} /> Download PDF Report
            </button>
          </div>

          {/* Table header */}
          <div className="alert-table-header">
            <span>Date</span><span>Time</span><span>Type</span>
            <span>Description</span><span>Location</span>
            <span>Duration</span><span>Map</span>
          </div>

          {/* List */}
          <div className="alerts-list">
            {filtered.length === 0 ? (
              <div className="alerts-empty">
                <div className="alerts-empty-emoji">🎉</div>
                <div className="alerts-empty-title">No alerts this week — great week!</div>
                <div className="alerts-empty-sub">Arjun had a perfectly safe week.</div>
              </div>
            ) : (
              filtered.map((alert, i) => (
                <AlertRow key={alert.id} alert={alert} index={i} />
              ))
            )}
          </div>

        </div>
      </div>
    </div>
  )
}
