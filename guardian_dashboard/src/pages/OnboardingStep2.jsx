import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { OnboardingHeader } from './OnboardingStep1'
import { Bell, MessageSquare, Mail, Smartphone } from 'lucide-react'

const PREFS = [
  {
    id: 'sos',
    emoji: '🔴',
    title: 'SOS Emergency',
    desc: 'Immediate SOS triggered by Arjun',
    locked: true,
    defaultOn: true,
  },
  {
    id: 'override',
    emoji: '🟡',
    title: 'High Risk Override Triggered',
    desc: 'When Drishti forces a stop for his safety',
    locked: false,
    defaultOn: true,
  },
  {
    id: 'nav',
    emoji: '🟢',
    title: 'Navigation Started / Ended',
    desc: 'Know exactly when he begins and ends a walk',
    locked: false,
    defaultOn: false,
  },
  {
    id: 'zone',
    emoji: '📍',
    title: 'User Leaves Safe Zone',
    desc: 'Alert when he walks outside a marked area',
    locked: false,
    defaultOn: true,
  },
  {
    id: 'battery',
    emoji: '🔋',
    title: 'Device Battery Low',
    desc: 'When his phone drops below 15%',
    locked: false,
    defaultOn: false,
  },
]

const CHANNELS = [
  { id: 'browser', label: 'Browser', icon: Bell },
  { id: 'email',   label: 'Email',   icon: Mail },
  { id: 'sms',     label: 'SMS',     icon: Smartphone },
  { id: 'whatsapp',label: 'WhatsApp',icon: MessageSquare },
]

function Toggle({ on, locked, onClick }) {
  return (
    <button
      className={`pref-toggle ${on ? 'on' : 'off'}`}
      onClick={locked ? undefined : onClick}
      style={{ cursor: locked ? 'default' : 'pointer' }}
      aria-label={on ? 'Enabled' : 'Disabled'}
    >
      <div className="pref-toggle-thumb" />
    </button>
  )
}

export default function OnboardingStep2() {
  const navigate = useNavigate()
  const [prefs, setPrefs] = useState(
    Object.fromEntries(PREFS.map(p => [p.id, p.defaultOn]))
  )
  const [channels, setChannels] = useState({ browser: true, email: true, sms: false, whatsapp: false })

  const togglePref = (id) => {
    setPrefs(prev => ({ ...prev, [id]: !prev[id] }))
  }
  const toggleChannel = (id) => {
    setChannels(prev => ({ ...prev, [id]: !prev[id] }))
  }

  return (
    <div className="onboarding-root">
      <OnboardingHeader step={1} />
      <div className="onboarding-body">
        <motion.div className="onboarding-card"
          initial={{ opacity:0, y:24 }} animate={{ opacity:1, y:0 }}
          transition={{ duration:.4, ease:'easeOut' }}>

          <h2 className="onboarding-heading">When should we notify you?</h2>
          <p className="onboarding-sub">
            Choose which events trigger alerts for Arjun's safety. You can change these anytime.
          </p>

          {/* Alert preference cards */}
          <div className="alert-pref-list">
            {PREFS.map((pref, i) => (
              <motion.div key={pref.id}
                className={`alert-pref-card ${pref.locked ? 'locked' : prefs[pref.id] ? 'active' : ''}`}
                onClick={() => !pref.locked && togglePref(pref.id)}
                initial={{ opacity:0, y:12 }} animate={{ opacity:1, y:0 }}
                transition={{ delay: i * 0.06 }}>
                <div className="alert-pref-icon">{pref.emoji}</div>
                <div className="alert-pref-info">
                  <div className="alert-pref-title">{pref.title}</div>
                  <div className="alert-pref-desc">{pref.desc}</div>
                </div>
                {pref.locked
                  ? <div className="pref-locked-badge">Always ON</div>
                  : <Toggle on={prefs[pref.id]} locked={false} onClick={() => togglePref(pref.id)} />
                }
              </motion.div>
            ))}
          </div>

          {/* Notification channels */}
          <div className="channel-section">
            <h4>NOTIFY ME VIA</h4>
            <div className="channel-list">
              {CHANNELS.map(ch => {
                const Icon = ch.icon
                return (
                  <label key={ch.id} className={`channel-chip ${channels[ch.id] ? 'active' : ''}`}
                    onClick={() => toggleChannel(ch.id)}>
                    <input type="checkbox" readOnly checked={channels[ch.id]} />
                    <Icon size={15} />
                    {ch.label}
                  </label>
                )
              })}
            </div>
          </div>

          <div style={{ display:'flex', gap:12, marginTop:32 }}>
            <button className="btn btn-outline" style={{ maxWidth:120 }}
              onClick={() => navigate('/setup/link')}>
              ← Back
            </button>
            <button className="btn btn-primary" onClick={() => navigate('/setup/zones')}>
              Continue to Safe Zones →
            </button>
          </div>
        </motion.div>
      </div>
    </div>
  )
}
