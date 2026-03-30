// src/pages/Settings.jsx — Guardian settings with Firestore persistence
import { useState, useEffect } from 'react'
import { doc, setDoc, serverTimestamp } from 'firebase/firestore'
import { updatePassword, EmailAuthProvider, reauthenticateWithCredential } from 'firebase/auth'
import { motion } from 'framer-motion'
import { User, Bell, Link2, Phone, Shield, Save, CheckCircle, AlertCircle } from 'lucide-react'
import Navbar  from '../components/Navbar'
import Sidebar from '../components/Sidebar'
import { db, auth } from '../config/firebase'
import { useAuth } from '../contexts/AuthContext'
import '../dashboard.css'
import '../pages.css'

const DEFAULT_USER = { id: 1, initials: 'AR', name: 'Arjun Sharma', status: 'Online', color: '#E8871A' }

function Section({ icon, title, children }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }}
      style={{
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(255,255,255,0.08)',
        borderRadius: 14, padding: '24px 28px', marginBottom: 20,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 20 }}>
        <span style={{ color: '#E8871A' }}>{icon}</span>
        <h3 style={{ fontSize: 15, fontWeight: 800, margin: 0 }}>{title}</h3>
      </div>
      {children}
    </motion.div>
  )
}

function Field({ label, children }) {
  return (
    <div style={{ marginBottom: 18 }}>
      <label style={{ display: 'block', fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.5)', marginBottom: 8, textTransform: 'uppercase', letterSpacing: 0.5 }}>
        {label}
      </label>
      {children}
    </div>
  )
}

function Input({ value, onChange, type = 'text', placeholder, disabled }) {
  return (
    <input
      type={type}
      value={value}
      onChange={onChange}
      placeholder={placeholder}
      disabled={disabled}
      style={{
        width: '100%', background: 'rgba(255,255,255,0.06)',
        border: '1px solid rgba(255,255,255,0.12)',
        borderRadius: 8, padding: '10px 14px',
        color: disabled ? 'rgba(255,255,255,0.3)' : 'white',
        fontSize: 14, outline: 'none',
        boxSizing: 'border-box',
        cursor: disabled ? 'not-allowed' : 'text',
      }}
    />
  )
}

function Toggle({ checked, onChange, label }) {
  return (
    <label style={{ display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer', marginBottom: 14 }}>
      <div
        onClick={() => onChange(!checked)}
        style={{
          width: 44, height: 24, borderRadius: 12,
          background: checked ? '#E8871A' : 'rgba(255,255,255,0.15)',
          position: 'relative', transition: 'background 0.25s', flexShrink: 0,
        }}
      >
        <div style={{
          position: 'absolute', width: 18, height: 18,
          borderRadius: '50%', background: 'white',
          top: 3, left: checked ? 23 : 3, transition: 'left 0.25s',
        }} />
      </div>
      <span style={{ fontSize: 14, color: 'rgba(255,255,255,0.8)' }}>{label}</span>
    </label>
  )
}

export default function Settings() {
  const { currentUser, guardianProfile, updateGuardianProfile } = useAuth()
  const [activeUser, setActiveUser] = useState(DEFAULT_USER)

  // Profile state
  const [displayName,    setDisplayName]    = useState('')
  const [phone,          setPhone]          = useState('')
  const [linkedUserUID,  setLinkedUserUID]  = useState('')

  // Notification prefs
  const [notifOverride,  setNotifOverride]  = useState(true)
  const [notifWarning,   setNotifWarning]   = useState(true)
  const [notifSOS,       setNotifSOS]       = useState(true)
  const [notifSession,   setNotifSession]   = useState(false)
  const [notifBattery,   setNotifBattery]   = useState(true)

  // Password change
  const [currentPwd,  setCurrentPwd]  = useState('')
  const [newPwd,      setNewPwd]      = useState('')
  const [confirmPwd,  setConfirmPwd]  = useState('')

  // UI state
  const [saving,      setSaving]      = useState(false)
  const [savedMsg,    setSavedMsg]    = useState('')
  const [errorMsg,    setErrorMsg]    = useState('')

  // Load from profile
  useEffect(() => {
    if (guardianProfile) {
      setDisplayName(guardianProfile.displayName || currentUser?.displayName || '')
      setPhone(guardianProfile.phone || '')
      setLinkedUserUID(guardianProfile.linked_user_uid || '')
      const prefs = guardianProfile.notification_prefs || {}
      setNotifOverride(prefs.override  ?? true)
      setNotifWarning( prefs.warning   ?? true)
      setNotifSOS(     prefs.sos       ?? true)
      setNotifSession( prefs.session   ?? false)
      setNotifBattery( prefs.battery   ?? true)
    }
  }, [guardianProfile, currentUser])

  const showMsg = (type, msg) => {
    if (type === 'ok') setSavedMsg(msg); else setErrorMsg(msg)
    setTimeout(() => { setSavedMsg(''); setErrorMsg('') }, 4000)
  }

  const handleSaveProfile = async () => {
    setSaving(true)
    try {
      await updateGuardianProfile({
        displayName: displayName.trim(),
        phone:       phone.trim(),
        linked_user_uid: linkedUserUID.trim() || null,
        notification_prefs: {
          override: notifOverride,
          warning:  notifWarning,
          sos:      notifSOS,
          session:  notifSession,
          battery:  notifBattery,
        },
      })
      showMsg('ok', '✓ Settings saved successfully')
    } catch (err) {
      showMsg('err', 'Failed to save: ' + err.message)
    } finally {
      setSaving(false)
    }
  }

  const handleChangePassword = async () => {
    setErrorMsg('')
    if (!currentPwd || !newPwd || !confirmPwd) { showMsg('err', 'Fill in all password fields'); return }
    if (newPwd !== confirmPwd)                  { showMsg('err', 'New passwords do not match');  return }
    if (newPwd.length < 6)                      { showMsg('err', 'Password must be 6+ characters'); return }

    setSaving(true)
    try {
      const credential = EmailAuthProvider.credential(currentUser.email, currentPwd)
      await reauthenticateWithCredential(auth.currentUser, credential)
      await updatePassword(auth.currentUser, newPwd)
      setCurrentPwd(''); setNewPwd(''); setConfirmPwd('')
      showMsg('ok', '✓ Password changed successfully')
    } catch (err) {
      const msg = err.code === 'auth/wrong-password' ? 'Current password is incorrect' : err.message
      showMsg('err', msg)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="page-root">
      <Navbar activeUser={activeUser} onUserChange={setActiveUser} isSOS={false} onBellClick={() => {}} bellCount={0} />
      <div className="page-body">
        <Sidebar activeUser={activeUser} />
        <div className="page-content" style={{ maxWidth: 720 }}>

          <div className="page-header">
            <div>
              <div className="page-title">Settings</div>
              <div className="page-breadcrumb">Guardian profile · Notifications · Security</div>
            </div>
          </div>

          {/* Status messages */}
          {savedMsg && (
            <motion.div initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }}
              style={{ display: 'flex', alignItems: 'center', gap: 8, background: 'rgba(16,185,129,0.12)',
                border: '1px solid rgba(16,185,129,0.3)', borderRadius: 8, padding: '10px 16px',
                marginBottom: 16, color: '#10B981', fontSize: 14 }}>
              <CheckCircle size={16} /> {savedMsg}
            </motion.div>
          )}
          {errorMsg && (
            <motion.div initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }}
              style={{ display: 'flex', alignItems: 'center', gap: 8, background: 'rgba(239,68,68,0.12)',
                border: '1px solid rgba(239,68,68,0.3)', borderRadius: 8, padding: '10px 16px',
                marginBottom: 16, color: '#EF4444', fontSize: 14 }}>
              <AlertCircle size={16} /> {errorMsg}
            </motion.div>
          )}

          {/* ── Profile Section ──────────────────────────────── */}
          <Section icon={<User size={18} />} title="Guardian Profile">
            <Field label="Display Name">
              <Input value={displayName} onChange={e => setDisplayName(e.target.value)} placeholder="Your name" />
            </Field>
            <Field label="Email Address">
              <Input value={currentUser?.email || ''} disabled />
            </Field>
            <Field label="Phone Number">
              <Input value={phone} onChange={e => setPhone(e.target.value)} placeholder="+91 98765 43210" type="tel" />
            </Field>
          </Section>

          {/* ── Linked User ──────────────────────────────────── */}
          <Section icon={<Link2 size={18} />} title="Linked User (Drishti-Link User)">
            <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.5)', marginBottom: 16, lineHeight: 1.6 }}>
              Enter the Firebase UID of the Drishti-Link user you want to monitor. You can find this in the mobile app under Profile → Account Info.
            </p>
            <Field label="User Firebase UID">
              <Input
                value={linkedUserUID}
                onChange={e => setLinkedUserUID(e.target.value)}
                placeholder="e.g. abc123xyz (from mobile app)"
              />
            </Field>
            {linkedUserUID && (
              <div style={{ fontSize: 12, color: '#10B981', display: 'flex', alignItems: 'center', gap: 6 }}>
                <CheckCircle size={12} /> User UID saved · Dashboard will show live data
              </div>
            )}
          </Section>

          {/* ── Notifications ────────────────────────────────── */}
          <Section icon={<Bell size={18} />} title="Notification Preferences">
            <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.5)', marginBottom: 16 }}>
              Choose which events trigger push notifications to your browser and phone.
            </p>
            <Toggle checked={notifSOS}      onChange={setNotifSOS}      label="🆘 SOS emergency alerts (always recommended)" />
            <Toggle checked={notifOverride}  onChange={setNotifOverride}  label="🔴 AI Override events — Arjun was stopped" />
            <Toggle checked={notifWarning}   onChange={setNotifWarning}   label="🟡 Warning events — hazard detected nearby" />
            <Toggle checked={notifBattery}   onChange={setNotifBattery}   label="🔋 Low battery alerts (below 20%)" />
            <Toggle checked={notifSession}   onChange={setNotifSession}   label="✅ Session start/end notifications" />
          </Section>

          {/* ── Security ─────────────────────────────────────── */}
          <Section icon={<Shield size={18} />} title="Change Password">
            <Field label="Current Password">
              <Input type="password" value={currentPwd} onChange={e => setCurrentPwd(e.target.value)} placeholder="Enter current password" />
            </Field>
            <Field label="New Password">
              <Input type="password" value={newPwd} onChange={e => setNewPwd(e.target.value)} placeholder="New password (6+ characters)" />
            </Field>
            <Field label="Confirm New Password">
              <Input type="password" value={confirmPwd} onChange={e => setConfirmPwd(e.target.value)} placeholder="Repeat new password" />
            </Field>
            <button
              onClick={handleChangePassword}
              disabled={saving}
              style={{
                background: 'transparent', border: '1px solid rgba(255,255,255,0.2)',
                color: 'white', padding: '10px 20px', borderRadius: 8,
                cursor: saving ? 'not-allowed' : 'pointer', fontSize: 14, fontWeight: 600,
              }}
            >
              Update Password
            </button>
          </Section>

          {/* ── Save button ───────────────────────────────────── */}
          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 8, paddingBottom: 40 }}>
            <button
              id="settings-save"
              className={`btn btn-primary ${saving ? 'btn-loading' : ''}`}
              onClick={handleSaveProfile}
              disabled={saving}
              style={{ minWidth: 160 }}
            >
              {!saving && <><Save size={16} /> Save All Settings</>}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
