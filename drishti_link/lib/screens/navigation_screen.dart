import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vibration/vibration.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';
import '../services/vision_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

// ── Navigation state ─────────────────────────────────────────────────────────

enum NavAlertState { clear, warning, danger }

// ── Hazard log entry ─────────────────────────────────────────────────────────

class _HazardEvent {
  final NavAlertState level;
  final String description;
  final String distanceLabel;
  final String timeLabel;

  const _HazardEvent({
    required this.level,
    required this.description,
    required this.distanceLabel,
    required this.timeLabel,
  });
}

// ── Live ML Pipeline ─────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with TickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────────────
  CameraController? _camera;
  bool _cameraReady = false;
  bool _cameraError = false;

  // ── Alert state ──────────────────────────────────────────────────
  NavAlertState _alertState = NavAlertState.clear;
  String _alertDesc = '';
  bool _alertVisible = false;

  // ── Collision score (0-100, lower = safer) ───────────────────────
  int _collisionScore = 12;

  // ── Hazard log ───────────────────────────────────────────────────
  final List<_HazardEvent> _hazardLog = [
    const _HazardEvent(
        level: NavAlertState.clear,
        description: 'Clear',
        distanceLabel: '—',
        timeLabel: '5m ago'),
    const _HazardEvent(
        level: NavAlertState.warning,
        description: 'Pothole',
        distanceLabel: '4m',
        timeLabel: '5m ago'),
    const _HazardEvent(
        level: NavAlertState.danger,
        description: 'Vehicle',
        distanceLabel: '8m',
        timeLabel: '3s ago'),
  ];
  bool _logExpanded = false;

  // ── Haptic ripple ─────────────────────────────────────────────────
  late final AnimationController _rippleCtrl;
  bool _rippling = false;

  // ── STT ─────────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _paused = false;

  // ── Live ML tracking ──────────────────────────────────────────────────
  final String _sessionId = const Uuid().v4();
  Timer? _frameTimer;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _initAll();
  }

  Future<void> _initAll() async {
    await Future.wait([_initCamera(), _initSpeech()]);
    if (!mounted) return;

    await context
        .read<VoiceService>()
        .speak('Theek hai. Main taiyaar hoon. Chalo.');
    _startLiveVisionLoop();
    _listenLoop();
  }

  // ── Camera ─────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = true);
        return;
      }
      final ctrl = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _camera = ctrl;
        _cameraReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _cameraError = true);
    }
  }

  // ── STT ────────────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize();
  }

  void _listenLoop() {
    if (!_speechAvailable || !mounted || _paused) return;
    setState(() => _isListening = true);
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 6),
      onResult: (r) {
        if (!r.finalResult) return;
        _handleCommand(r.recognizedWords.toLowerCase());
        Future.delayed(const Duration(milliseconds: 800), _listenLoop);
      },
    );
  }

  Future<void> _handleCommand(String words) async {
    final voice = context.read<VoiceService>();
    if (words.contains('kya hai') || words.contains('aage')) {
      switch (_alertState) {
        case NavAlertState.clear:
          await voice.speak('Rasta saaf hai. Aage badho.');
          break;
        case NavAlertState.warning:
          await voice.speak(_alertDesc);
          break;
        case NavAlertState.danger:
          await voice.speak('DANGER! $_alertDesc');
          break;
      }
    } else if (words.contains('ruko') || words.contains('pause')) {
      setState(() => _paused = true);
      _speech.stop();
      await voice.speak('Theek hai. Navigation pause ho gaya.');
    } else if (words.contains('help') || words.contains('sos')) {
      await voice.speak('Guardian ko call kar rahi hoon. Ruko.');
      _triggerSOS();
    } else if (words.contains('ghar')) {
      await voice.speak('Ghar ka route set kar rahi hoon.');
    } else if (words.contains('priya') || words.contains('guardian')) {
      await voice.speak('Priya online hain. Aapki location share ho rahi hai.');
    }
  }

  // ── Live backend integration ───────────────────────────────────────
  void _startLiveVisionLoop() {
    _frameTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _paused || _isAnalyzing || !_cameraReady || _camera == null) return;
      _isAnalyzing = true;
      try {
        final xFile = await _camera!.takePicture();
        final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest_fallback_id';

        final response = await VisionService.analyzeImage(
          image: xFile,
          userId: userId,
          sessionId: _sessionId,
          lat: 0.0,
          lng: 0.0,
        );

        if (response != null && mounted && !_paused) {
          NavAlertState state = NavAlertState.clear;
          if (response.overallPc >= 65) {
             state = NavAlertState.danger;
          } else if (response.overallPc >= 30) {
             state = NavAlertState.warning;
          }

          // Generate description
          String desc = state == NavAlertState.clear ? 'Clear' : response.ttsMessage;
          if (desc.isEmpty && state != NavAlertState.clear) desc = 'Hazard Detected';

          await _applyAlertState(
             state,
             desc,
             response.hazards.isNotEmpty ? '${response.hazards.first['distance_m']}m' : '',
             response.ttsMessage,
             response.shouldOverride ? 'stop' : (state == NavAlertState.clear ? 'go' : 'left'),
             backendPc: response.overallPc,
          );
        }
      } catch (e) {
        debugPrint('Vision Loop Error: $e');
      } finally {
        if (mounted) _isAnalyzing = false;
      }
    });
  }

  Future<void> _applyAlertState(
    NavAlertState state,
    String desc,
    String dist,
    String voice,
    String hapticType,
    {int backendPc = 0}
  ) async {
    if (!mounted) return;

    setState(() {
      _alertState = state;
      _alertDesc = desc;
      _alertVisible = state != NavAlertState.clear;
      _collisionScore = backendPc;
    });

    if (state == NavAlertState.danger) {
      HapticFeedback.heavyImpact();
      await _fireRipple();
      _strongVibration();
    } else if (state == NavAlertState.warning) {
      HapticFeedback.mediumImpact();
      _leftPulse();
    } else if (hapticType == 'go') {
      HapticFeedback.lightImpact();
      await _fireRipple();
    }

    if (dist.isNotEmpty && voice.isNotEmpty) {
      _addToLog(state, desc, dist);
    }
    if (voice.isNotEmpty && mounted) {
      await context.read<VoiceService>().speak(voice);
    }
  }

  Future<void> _fireRipple() async {
    if (!mounted) return;
    setState(() => _rippling = true);
    _rippleCtrl.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _rippling = false);
  }

  void _leftPulse() async {
    for (int i = 0; i < 3; i++) {
      await Vibration.vibrate(duration: 80, amplitude: 128);
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _strongVibration() async {
    await Vibration.vibrate(duration: 600, amplitude: 255);
    await Future.delayed(const Duration(milliseconds: 400));
    await Vibration.vibrate(duration: 600, amplitude: 255);
  }

  void _addToLog(NavAlertState level, String desc, String dist) {
    if (!mounted) return;
    setState(() {
      _hazardLog.insert(
          0,
          _HazardEvent(
            level: level,
            description: desc,
            distanceLabel: dist,
            timeLabel: 'just now',
          ));
      if (_hazardLog.length > 5) _hazardLog.removeLast();
    });
  }

  Future<void> _triggerSOS() async {
    HapticFeedback.heavyImpact();
    await context.read<VoiceService>().speak(
          'SOS bhej rahi hoon. Priya ko notify kar rahi hoon.',
        );
    if (mounted) Navigator.pushNamed(context, '/sos');
  }

  Future<void> _stopNavigation() async {
    await context
        .read<VoiceService>()
        .speak('Navigation band kar rahi hoon. Ghar safe pohunch jao.');
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    _camera?.dispose();
    _speech.stop();
    _frameTimer?.cancel();
    super.dispose();
  }

  // ── BUILD ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ════════════════════════════════════════════════════════
          // LAYER 1 — Camera / fallback background
          // ════════════════════════════════════════════════════════
          _CameraBackground(
            controller: _camera,
            isReady: _cameraReady,
            hasError: _cameraError,
          ),

          // ════════════════════════════════════════════════════════
          // LAYER 2 — Danger full-screen flash
          // ════════════════════════════════════════════════════════
          if (_alertState == NavAlertState.danger)
            _DangerFlash()
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 250.ms)
                .then()
                .fadeOut(duration: 250.ms),

          // ════════════════════════════════════════════════════════
          // LAYER 3 — Haptic ripple rings from center
          // ════════════════════════════════════════════════════════
          if (_rippling)
            _RippleOverlay(
                controller: _rippleCtrl,
                color: _alertState == NavAlertState.danger
                    ? AppColors.hazardRed
                    : AppColors.safeGreen),

          // ════════════════════════════════════════════════════════
          // LAYER 4 — Top glassmorphism bar
          // ════════════════════════════════════════════════════════
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSizes.sm,
            left: AppSizes.lg,
            right: AppSizes.lg,
            child: _TopGlassBar(
              collisionScore: _collisionScore,
              alertState: _alertState,
              onSOS: _triggerSOS,
            ),
          ),

          // ════════════════════════════════════════════════════════
          // LAYER 5 — Alert card (warning / danger)
          // ════════════════════════════════════════════════════════
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            bottom: _alertVisible ? 180 : -220,
            left: AppSizes.lg,
            right: AppSizes.lg,
            child: _alertVisible
                ? _AlertCard(
                    state: _alertState,
                    description: _alertDesc,
                  )
                : const SizedBox.shrink(),
          ),

          // ════════════════════════════════════════════════════════
          // LAYER 6 — Bottom bar (voice indicator + stop button)
          // ════════════════════════════════════════════════════════
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomBar(
              isListening: _isListening,
              isPaused: _paused,
              logExpanded: _logExpanded,
              hazardLog: _hazardLog,
              onToggleLog: () => setState(() => _logExpanded = !_logExpanded),
              onStop: _stopNavigation,
              onResume: () {
                setState(() => _paused = false);
                _listenLoop();
                context
                    .read<VoiceService>()
                    .speak('Navigation resume ho gaya.');
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CAMERA BACKGROUND
// ─────────────────────────────────────────────────────────────────────────────

class _CameraBackground extends StatelessWidget {
  final CameraController? controller;
  final bool isReady;
  final bool hasError;

  const _CameraBackground({
    required this.controller,
    required this.isReady,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    if (hasError || !isReady || controller == null) {
      // Elegant fallback — simulated camera noise gradient
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A1628),
              Color(0xFF0D1F3C),
              Color(0xFF050A14),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasError ? Icons.camera_alt_outlined : Icons.videocam_rounded,
                color: AppColors.navyLight,
                size: 64,
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                hasError ? 'Camera unavailable' : 'Camera starting...',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller!.value.previewSize?.height ?? 1,
          height: controller!.value.previewSize?.width ?? 1,
          child: CameraPreview(controller!),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP GLASSMORPHISM BAR
// ─────────────────────────────────────────────────────────────────────────────

class _TopGlassBar extends StatelessWidget {
  final int collisionScore;
  final NavAlertState alertState;
  final VoidCallback onSOS;

  const _TopGlassBar({
    required this.collisionScore,
    required this.alertState,
    required this.onSOS,
  });

  Color get _scoreColor {
    if (collisionScore < 30) return AppColors.safeGreen;
    if (collisionScore < 65) return const Color(0xFFFFD600);
    return AppColors.hazardRed;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              // ── Navigate badge ───────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.safeGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.safeGreen.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.navigation_rounded,
                        color: AppColors.safeGreen, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'NAVIGATE',
                      style: TextStyle(
                        color: AppColors.safeGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 800.ms, begin: 0.6),

              const Spacer(),

              // ── Collision score ──────────────────────────────
              Semantics(
                label: 'Collision score: $collisionScore percent',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PC: $collisionScore%',
                      style: TextStyle(
                        color: _scoreColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      collisionScore < 30
                          ? 'Safe'
                          : collisionScore < 65
                              ? 'Caution'
                              : 'Danger',
                      style: TextStyle(
                        color: _scoreColor.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── SOS button ───────────────────────────────────
              Semantics(
                label: 'SOS — Emergency. Tap to call guardian.',
                button: true,
                child: GestureDetector(
                  onTap: onSOS,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.hazardRed,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.hazardRed.withValues(alpha: 0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Text(
                      '🆘 SOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
                      end: 1.06, duration: 1000.ms, curve: Curves.easeInOut),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final NavAlertState state;
  final String description;

  const _AlertCard({required this.state, required this.description});

  bool get _isDanger => state == NavAlertState.danger;

  Color get _cardColor =>
      _isDanger ? AppColors.hazardRed : const Color(0xFFFFD600);

  IconData get _icon =>
      _isDanger ? Icons.block_rounded : Icons.warning_amber_rounded;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: description,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius + 4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              color: _cardColor.withValues(alpha: _isDanger ? 0.25 : 0.18),
              borderRadius: BorderRadius.circular(AppSizes.cardRadius + 4),
              border: Border.all(
                color: _cardColor.withValues(alpha: 0.7),
                width: _isDanger ? 2.5 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _cardColor.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Row(
              children: [
                // Large icon
                Icon(_icon, color: _cardColor, size: 56)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(
                      end: _isDanger ? 1.15 : 1.08,
                      duration: _isDanger ? 500.ms : 800.ms,
                    ),

                const SizedBox(width: AppSizes.lg),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        description,
                        style: TextStyle(
                          color: _cardColor,
                          fontSize: _isDanger ? 22 : 20,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isDanger
                            ? 'Haptic: STOP vibration active'
                            : 'Haptic: Left pulses',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DANGER FULL-SCREEN FLASH
// ─────────────────────────────────────────────────────────────────────────────

class _DangerFlash extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        color: AppColors.hazardRed.withValues(alpha: 0.18),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HAPTIC RIPPLE OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _RippleOverlay extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  const _RippleOverlay({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final t = controller.value;
          return CustomPaint(
            painter: _RipplePainter(progress: t, color: color),
          );
        },
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.longestSide * 0.75;

    for (int i = 0; i < 3; i++) {
      final delay = i * 0.25;
      final p = ((progress - delay).clamp(0.0, 1.0));
      if (p <= 0) continue;
      final radius = maxRadius * p;
      final alpha = (1 - p) * 0.5;
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 - 2 * p;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM BAR — voice status + hazard log + stop button
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final bool isListening;
  final bool isPaused;
  final bool logExpanded;
  final List<_HazardEvent> hazardLog;
  final VoidCallback onToggleLog;
  final VoidCallback onStop;
  final VoidCallback onResume;

  const _BottomBar({
    required this.isListening,
    required this.isPaused,
    required this.logExpanded,
    required this.hazardLog,
    required this.onToggleLog,
    required this.onStop,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.only(
            left: AppSizes.lg,
            right: AppSizes.lg,
            top: AppSizes.md,
            bottom: MediaQuery.of(context).padding.bottom + AppSizes.md,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Hazard log toggle ─────────────────────────────
              GestureDetector(
                onTap: onToggleLog,
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded,
                        color: AppColors.textMuted, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Hazard Log',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5),
                    ),
                    const Spacer(),
                    Icon(
                      logExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                  ],
                ),
              ),

              // ── Hazard log entries ────────────────────────────
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: logExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Column(
                  children: [
                    const SizedBox(height: AppSizes.sm),
                    ...hazardLog.take(3).map((e) => _HazardLogRow(event: e)),
                  ],
                ),
                secondChild: const SizedBox.shrink(),
              ),

              const SizedBox(height: AppSizes.sm),

              // ── Voice status row ───────────────────────────────
              Row(
                children: [
                  // Mic pulsing indicator
                  AnimatedContainer(
                    duration: AppDurations.medium,
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isListening
                          ? AppColors.saffron.withValues(alpha: 0.2)
                          : Colors.transparent,
                      border: Border.all(
                        color: isListening ? AppColors.saffron : Colors.white24,
                      ),
                    ),
                    child: Icon(
                      isPaused ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: isListening ? AppColors.saffron : Colors.white38,
                      size: 16,
                    ),
                  )
                      .animate(
                          onPlay: (c) =>
                              isListening ? c.repeat(reverse: true) : null)
                      .scaleXY(end: isListening ? 1.12 : 1.0, duration: 900.ms),

                  const SizedBox(width: AppSizes.sm),

                  Expanded(
                    child: Semantics(
                      label: isPaused
                          ? 'Navigation paused. Tap resume to continue.'
                          : 'Drishti is listening.',
                      child: Text(
                        isPaused
                            ? '⏸ Paused — "Resume" bolein'
                            : '🎙️ Drishti sun rahi hai...',
                        style: TextStyle(
                          color: isPaused
                              ? AppColors.hazardRed.withValues(alpha: 0.8)
                              : Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  // Resume or —
                  if (isPaused)
                    GestureDetector(
                      onTap: onResume,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.safeGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  AppColors.safeGreen.withValues(alpha: 0.5)),
                        ),
                        child: const Text('Resume',
                            style: TextStyle(
                                color: AppColors.safeGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: AppSizes.md),

              // ── Stop navigation button ─────────────────────────
              Semantics(
                label: 'Stop navigation',
                button: true,
                child: GestureDetector(
                  onTap: onStop,
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(AppSizes.buttonRadius),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: const Center(
                      child: Text(
                        'NAVIGATION BAND KARO',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HAZARD LOG ROW
// ─────────────────────────────────────────────────────────────────────────────

class _HazardLogRow extends StatelessWidget {
  final _HazardEvent event;
  const _HazardLogRow({required this.event});

  Color get _color {
    switch (event.level) {
      case NavAlertState.danger:
        return AppColors.hazardRed;
      case NavAlertState.warning:
        return const Color(0xFFFFD600);
      case NavAlertState.clear:
        return AppColors.safeGreen;
    }
  }

  String get _dot {
    switch (event.level) {
      case NavAlertState.danger:
        return '🔴';
      case NavAlertState.warning:
        return '🟡';
      case NavAlertState.clear:
        return '🟢';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(_dot, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${event.description}  ${event.distanceLabel}',
              style: TextStyle(
                  color: _color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            event.timeLabel,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
