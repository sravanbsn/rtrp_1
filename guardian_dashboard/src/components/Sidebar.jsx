import { useState } from 'react'

const NAV_ITEMS = [
  { icon: '📍', label: 'Live Monitor', id: 'monitor' },
  { icon: '🔔', label: 'Alerts',       id: 'alerts' },
  { icon: '🗺️', label: 'Route History',id: 'routes' },
  { icon: '🛡️', label: 'Safe Zones',   id: 'zones' },
  { icon: '⚙️', label: 'Settings',     id: 'settings' },
]

export default function Sidebar({ activeUser }) {
  const [active, setActive] = useState('monitor')

  return (
    <aside className="dash-sidebar">
      {NAV_ITEMS.map(item => (
        <div key={item.id}
          className={`sidebar-item ${active === item.id ? 'active' : ''}`}
          onClick={() => setActive(item.id)}
          title={item.label}>
          <span className="sidebar-icon">{item.icon}</span>
          <span className="sidebar-label">{item.label}</span>
        </div>
      ))}

      <div className="sidebar-spacer" />

      {/* User mini status card */}
      <div className="sidebar-user-card">
        <div className="sidebar-user-row">
          <div className="sidebar-user-avatar"
            style={{ background: `linear-gradient(135deg, ${activeUser.color}33, ${activeUser.color}22)`,
              borderColor: `${activeUser.color}55` }}>
            {activeUser.initials}
          </div>
          <span className="sidebar-user-name">{activeUser.name.split(' ')[0]}</span>
        </div>
        <div className="sidebar-stats-row">
          <div className="sidebar-stat">
            <span>🔋</span>
            <span>78%</span>
          </div>
          <div className="sidebar-stat">
            <span>📡</span>
            <span>GPS Strong</span>
          </div>
        </div>
      </div>
    </aside>
  )
}
