import { useState, useRef, useEffect } from 'react'
import { Bell, ChevronDown, Check } from 'lucide-react'

const USERS = [
  { id: 1, initials: 'AR', name: 'Arjun Sharma', status: 'Navigating', color: '#E8871A' },
  { id: 2, initials: 'PM', name: 'Priya Mehta',  status: 'Home',       color: '#3B82F6' },
]

export default function Navbar({ activeUser, onUserChange, isSOS, onBellClick, bellCount }) {
  const [dropOpen, setDropOpen] = useState(false)
  const dropRef = useRef()

  useEffect(() => {
    const h = (e) => { if (dropRef.current && !dropRef.current.contains(e.target)) setDropOpen(false) }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [])

  return (
    <nav className="dash-nav">
      {/* Logo */}
      <div className="dash-nav-logo">
        <div className="dash-nav-logo-icon">👁</div>
        <div className="dash-nav-logo-text">Drishti<span>Link</span></div>
      </div>

      {/* User selector */}
      <div className="nav-user-selector" onClick={() => setDropOpen(v => !v)} ref={dropRef}>
        <div className="nav-user-avatar-sm" style={{ background: activeUser.color }}>
          {activeUser.initials}
        </div>
        {activeUser.name}
        <ChevronDown size={13} style={{ color:'rgba(255,255,255,.45)', marginLeft:2 }} />

        {dropOpen && (
          <div className="user-dropdown">
            {USERS.map(u => (
              <div key={u.id}
                className={`user-dropdown-item ${u.id === activeUser.id ? 'active' : ''}`}
                onClick={() => { onUserChange(u); setDropOpen(false) }}>
                <div style={{
                  width:24, height:24, borderRadius:'50%', background:u.color,
                  display:'flex', alignItems:'center', justifyContent:'center',
                  fontSize:10, fontWeight:800, color:'white', flexShrink:0,
                }}>
                  {u.initials}
                </div>
                <div>
                  <div style={{ fontWeight:700 }}>{u.name}</div>
                  <div style={{ fontSize:10, color:'rgba(255,255,255,.45)' }}>{u.status}</div>
                </div>
                {u.id === activeUser.id && <Check size={13} style={{ marginLeft:'auto' }} />}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Status pill */}
      <div className={`nav-status-pill ${isSOS ? 'sos' : ''}`}>
        <div className="status-dot" />
        {isSOS ? '🆘 SOS ACTIVE' : `🟢 ${activeUser.status} • Live`}
      </div>

      {/* Bell */}
      <button className="nav-bell" onClick={onBellClick}>
        <Bell size={16} />
        {bellCount > 0 && <div className="bell-badge">{bellCount}</div>}
      </button>

      {/* Guardian avatar */}
      <div className="nav-guardian">
        <div className="nav-guardian-avatar">GD</div>
        <div className="nav-guardian-name">Guardian</div>
      </div>
    </nav>
  )
}
