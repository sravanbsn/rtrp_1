import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vibration/vibration.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';

// Warm crimson — not harsh red
const _crimson = Color(0xFF8B1A1A);
const _crimsonMid = Color(0xFFB22222);

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with TickerProviderStateMixin {
  // ── Pulse rings animation ────────────────────────────────────────
  late final AnimationController _ringCtrl;

  // ── Timer since SOS ──────────────────────────────────────────────
  int _secondsElapsed = 0;
  Timer? _ticker;
  Timer? _repeatSpeakTimer;

  // ── Cancel confirmation flow ─────────────────────────────────────
  bool _showCancel = false;
  bool _cancelled = false;

  // ── STT ─────────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _startAll();
  }

  Future<void> _startAll() async {
    // Strong vibration burst to confirm SOS
    HapticFeedback.heavyImpact();
    await Vibration.vibrate(duration: 800, amplitude: 255);

    _speechAvailable = await _speech.initialize();

    // Start elapsed timer
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });

    if (!mounted) return;

    // Opening speech
    await context.read<VoiceService>().speak(
          'Arjun, ghabraiye mat. Main Priya ko call kar rahi hoon. '
          'Aap wahan rukein. Sab theek ho jaayega.',
        );

    // Repeat every 15s
    _repeatSpeakTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || _cancelled) return;
      await context.read<VoiceService>().speak(
            'Priya ko pata chal gaya. Woh aa rahi hain.',
          );
    });

    // Listen for cancel voice command
    _listenForCancel();
  }

  void _listenForCancel() {
    if (!_speechAvailable || !mounted) return;
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 10),
      onResult: (r) {
        if (!r.finalResult) return;
        final w = r.recognizedWords.toLowerCase();
        if (w.contains('theek') ||
            w.contains('cancel') ||
            w.contains('ruk') ||
            w.contains('band')) {
          _confirmCancel();
        }
      },
    );
  }

  Future<void> _confirmCancel() async {
    if (!mounted) return;
    setState(() => _showCancel = true);
    await context.read<VoiceService>().speak(
          'Pakka theek hain? Alert cancel kar deti hoon.',
        );
    _listenForFinalConfirm();
  }

  void _listenForFinalConfirm() {
    if (!_speechAvailable || !mounted) return;
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        if (!r.finalResult) return;
        final w = r.recognizedWords.toLowerCase();
        if (w.contains('haan') || w.contains('yes')) {
          _cancelSOS();
        } else if (w.contains('nahi') || w.contains('no')) {
          setState(() => _showCancel = false);
          _listenForCancel();
        }
      },
    );
  }

  Future<void> _cancelSOS() async {
    setState(() => _cancelled = true);
    HapticFeedback.mediumImpact();
    await context.read<VoiceService>().speak(
          'Alert cancel ho gaya. Aap safe hain. Bahut acha!',
        );
    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) Navigator.pop(context);
  }

  String _formatElapsed() {
    if (_secondsElapsed < 60) return '$_secondsElapsed seconds ago';
    final m = _secondsElapsed ~/ 60;
    final s = _secondsElapsed % 60;
    return '$m min ${s}s ago';
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _ticker?.cancel();
    _repeatSpeakTimer?.cancel();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cancelled) return _CancelledView();

    return Scaffold(
      backgroundColor: _crimson,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Warm radial glow ───────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.1),
                radius: 0.9,
                colors: [
                  Color(0xFFCC2222),
                  _crimson,
                  Color(0xFF4A0A0A),
                ],
              ),
            ),
          ),

          // ── Pulsing SOS rings ──────────────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: _ringCtrl,
              builder: (_, __) {
                final t = _ringCtrl.value;
                return CustomPaint(
                  painter: _SosRingPainter(progress: t),
                  child: const SizedBox(width: 240, height: 240),
                );
              },
            ),
          ),

          // ── Main content ─────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: AppSizes.lg),

                // ── SOS label ───────────────────────────────────
                const Text(
                  '🆘 SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fadeIn(duration: 600.ms),

                const SizedBox(height: AppSizes.sm),

                // ── Main heading ────────────────────────────────
                Semantics(
                  liveRegion: true,
                  child: const Text(
                    'PRIYA KO BATAYA\nJA RAHA HAI',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: -0.1, end: 0),

                const SizedBox(height: AppSizes.xl),

                // ── Guardian avatar (calling animation) ─────────
                _GuardianCallingWidget(),

                const SizedBox(height: AppSizes.xl),

                // ── Live location pill ──────────────────────────
                Semantics(
                  label: 'Live location is being shared',
                  child: _LiveLocationPill(),
                ),

                const SizedBox(height: AppSizes.md),

                // ── Elapsed time ────────────────────────────────
                Semantics(
                  label: 'SOS sent ${_formatElapsed()}',
                  child: Text(
                    '⏱ ${_formatElapsed()}',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const Spacer(),

                // ── Buttons ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                  child: _showCancel
                      ? _CancelConfirmButtons(
                          onYes: _cancelSOS,
                          onNo: () {
                            setState(() => _showCancel = false);
                            _listenForCancel();
                          },
                        )
                      : _ActionButtons(
                          onCancel: _confirmCancel,
                          onCall: () {
                            context.read<VoiceService>().speak(
                                  'Priya ko call kar rahi hoon.',
                                );
                          },
                        ),
                ),

                const SizedBox(height: AppSizes.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── SOS ring painter ─────────────────────────────────────────────────────────

class _SosRingPainter extends CustomPainter {
  final double progress;
  const _SosRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 4; i++) {
      final delay = i * 0.22;
      final p = ((progress - delay) % 1.0).clamp(0.0, 1.0);
      final radius = (size.width / 2) * (0.35 + 0.65 * p);
      final alpha = (1 - p) * 0.55;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 - 2 * p;
      canvas.drawCircle(center, radius, paint);
    }
    // Center SOS circle
    canvas.drawCircle(
      center,
      size.width * 0.175,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'SOS',
        style: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_SosRingPainter old) => old.progress != progress;
}

// ── Guardian calling widget ───────────────────────────────────────────────────

class _GuardianCallingWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar with ring
        Stack(
          alignment: Alignment.center,
          children: [
            // Calling ring
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38, width: 2),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(end: 1.2, duration: 1000.ms),

            // Avatar
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.2),
                border: Border.all(color: Colors.white70, width: 2.5),
              ),
              child: const Center(
                child: Text('PS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    )),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSizes.sm),

        // Name + calling
        const Text(
          'Priya Sharma',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Calling...',
          style: TextStyle(
              color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fadeIn(duration: 600.ms),
      ],
    );
  }
}

// ── Live location pill ───────────────────────────────────────────────────────

class _LiveLocationPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.safeGreen,
              shape: BoxShape.circle,
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(end: 1.5, duration: 700.ms),
          const SizedBox(width: 8),
          const Text(
            'Live location share ho rahi hai',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Action buttons ────────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onCall;

  const _ActionButtons({required this.onCancel, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Cancel — full width white
        Semantics(
          label: 'I am okay. Cancel SOS alert.',
          button: true,
          child: ElevatedButton.icon(
            onPressed: onCancel,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _crimsonMid,
              minimumSize: const Size(double.infinity, AppSizes.minTouchTarget),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.buttonRadius)),
            ),
            icon: const Icon(Icons.check_circle_outline_rounded,
                color: _crimsonMid, size: 20),
            label: const Text(
              'Main Theek Hoon — Cancel',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: _crimsonMid),
            ),
          ),
        ),

        const SizedBox(height: AppSizes.md),

        // Direct call — outlined
        Semantics(
          label: 'Call Priya directly',
          button: true,
          child: OutlinedButton.icon(
            onPressed: onCall,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, AppSizes.minTouchTarget),
              side: const BorderSide(color: Colors.white54, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.buttonRadius)),
            ),
            icon: const Icon(Icons.phone_rounded,
                color: Colors.white70, size: 20),
            label: const Text('Priya ko Call Karo',
                style: TextStyle(color: Colors.white70)),
          ),
        ),
      ],
    );
  }
}

// ── Cancel confirmation buttons ───────────────────────────────────────────────

class _CancelConfirmButtons extends StatelessWidget {
  final VoidCallback onYes;
  final VoidCallback onNo;

  const _CancelConfirmButtons({required this.onYes, required this.onNo});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Pakka theek hain?',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSizes.md),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: onYes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _crimsonMid,
                  minimumSize: const Size(0, AppSizes.minTouchTarget),
                ),
                child: const Text('Haan, Theek Hoon',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: _crimsonMid)),
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: OutlinedButton(
                onPressed: onNo,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.minTouchTarget),
                  side: const BorderSide(color: Colors.white54),
                ),
                child:
                    const Text('Nahi', style: TextStyle(color: Colors.white70)),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }
}

// ── Cancelled relief view ─────────────────────────────────────────────────────

class _CancelledView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.safeGreen, size: 96),
            const SizedBox(height: AppSizes.lg),
            Text('Alert Cancel Ho Gaya',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: AppSizes.sm),
            Text('Aap Safe Hain 🙏',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.safeGreen, fontWeight: FontWeight.w700)),
          ],
        ).animate().fadeIn(duration: 500.ms).scaleXY(begin: 0.8, end: 1.0),
      ),
    );
  }
}
