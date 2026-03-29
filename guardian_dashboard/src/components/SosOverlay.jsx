import { useEffect, useRef } from 'react'
import { motion } from 'framer-motion'

export default function SosOverlay({ onAcknowledge }) {
  // Play browser beep via AudioContext
  const audioCtxRef = useRef(null)

  useEffect(() => {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)()
      audioCtxRef.current = ctx

      const playBeep = (freq, time) => {
        const osc  = ctx.createOscillator()
        const gain = ctx.createGain()
        osc.connect(gain)
        gain.connect(ctx.destination)
        osc.frequency.setValueAtTime(freq, ctx.currentTime + time)
        gain.gain.setValueAtTime(0.3, ctx.currentTime + time)
        gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + time + 0.3)
        osc.start(ctx.currentTime + time)
        osc.stop(ctx.currentTime + time + 0.35)
      }

      // SOS pattern: 3 short, 3 long, 3 short
      const pattern = [0, .4, .8, 1.4, 2.0, 2.6, 3.2, 3.6, 4.0]
      pattern.forEach((t, i) => playBeep(i < 3 || i > 5 ? 880 : 440, t))

      // After first sequence, repeat every 5s
      const iv = setInterval(() => {
        pattern.forEach((t, i) => playBeep(i < 3 || i > 5 ? 880 : 440, t))
      }, 5000)

      return () => {
        clearInterval(iv)
        ctx.close()
      }
    } catch {
      // AudioContext not available
    }
  }, [])

  return (
    <motion.div className="sos-overlay"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: .3 }}>

      {/* Pulsing rings */}
      <div className="sos-pulse-rings">
        <div className="sos-ring" />
        <div className="sos-ring" />
        <div className="sos-ring" />
      </div>

      <div className="sos-content">
        <motion.div className="sos-emoji"
          animate={{ scale: [1, 1.12, 1] }}
          transition={{ repeat: Infinity, duration: 1.2, ease: 'easeInOut' }}>
          🆘
        </motion.div>

        <motion.h1 className="sos-headline"
          animate={{ opacity: [1, .75, 1] }}
          transition={{ repeat: Infinity, duration: 1.5 }}>
          ARJUN NEEDS HELP
        </motion.h1>

        <p className="sos-sub">SOS triggered at 2:45 PM</p>
        <p className="sos-location">📍 Gandhi Nagar Junction · Last known location</p>

        <motion.button className="sos-respond-btn"
          onClick={onAcknowledge}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.97 }}>
          ✅ I Am Responding
        </motion.button>

        <p style={{ marginTop:16, fontSize:12, color:'rgba(255,255,255,.35)' }}>
          This overlay cannot be dismissed until you acknowledge.
        </p>
      </div>
    </motion.div>
  )
}
