import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:local_auth/local_auth.dart';

import '../../core/theme.dart';
import '../../services/voice_service.dart';
import '../../widgets/drishti_voice_bar.dart';

class LoginBiometricScreen extends StatefulWidget {
  const LoginBiometricScreen({super.key});

  @override
  State<LoginBiometricScreen> createState() => _LoginBiometricScreenState();
}

class _LoginBiometricScreenState extends State<LoginBiometricScreen>
    with SingleTickerProviderStateMixin {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isAuthenticating = false;
  bool _showFaceId = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const String _openLine =
      'Fingerprint lagayein, ya boliye "Drishti kholo".';
  static const String _wakePhrase = 'drishti kholo';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _initAndSpeak();
  }

  Future<void> _initAndSpeak() async {
    _speechAvailable = await _speech.initialize();

    // Check if Face ID is available
    final biometrics = await _localAuth.getAvailableBiometrics();
    setState(() {
      _showFaceId = biometrics.contains(BiometricType.face);
    });

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await context.read<VoiceService>().speak(_openLine);
    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;
    _startWakeListener();
  }

  /// Continuously listens for the wake phrase "Drishti kholo"
  void _startWakeListener() {
    if (!_speechAvailable || !mounted) return;
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        if (words.contains(_wakePhrase) ||
            words.contains('kholo') ||
            words.contains('open drishti') ||
            words.contains('unlock')) {
          _authenticate();
        }
      },
      onSoundLevelChange: null,
    );
  }

  Future<void> _authenticate({bool useFace = false}) async {
    if (_isAuthenticating) return;
    setState(() => _isAuthenticating = true);
    _speech.stop();

    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: useFace
            ? 'Drishti-Link mein enter karne ke liye Face ID use karein'
            : 'Drishti-Link mein enter karne ke liye fingerprint lagayein',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!mounted) return;

      if (didAuth) {
        await context.read<VoiceService>().speak('Perfect. Andar chalte hain.');
        await Future.delayed(const Duration(milliseconds: 1400));
        if (mounted) Navigator.pushReplacementNamed(context, '/home');
      } else {
        await context.read<VoiceService>().speak(
              'Pehchaan nahi hui. Dobara koshish karein.',
            );
        setState(() => _isAuthenticating = false);
        _startWakeListener();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAuthenticating = false);
      await context.read<VoiceService>().speak(
            'Biometric kaam nahi kar raha. Phone number se login karein.',
          );
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ── TOP — orb glow ─────────────────────────────────
                SizedBox(
                  height: size.height * 0.40,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background radial glow
                        Container(
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                AppColors.saffronGlow,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),

                        // Pulsing fingerprint button
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, __) => Transform.scale(
                            scale: _isAuthenticating ? 1.0 : _pulseAnim.value,
                            child: GestureDetector(
                              onTap: () => _authenticate(),
                              child: Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const RadialGradient(
                                    colors: [
                                      AppColors.saffronLight,
                                      AppColors.saffron,
                                      AppColors.saffronDark,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.saffron.withOpacity(0.5),
                                      blurRadius: 36,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                                child: _isAuthenticating
                                    ? const CircularProgressIndicator(
                                        color: AppColors.navyDeep,
                                        strokeWidth: 3,
                                      )
                                    : const Icon(
                                        Icons.fingerprint_rounded,
                                        color: AppColors.navyDeep,
                                        size: 70,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── BOTTOM — panel ──────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: AppColors.navyMid,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Wapas Aa Gaaye! 👋',
                            style: Theme.of(context).textTheme.headlineLarge,
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.sm),

                          Text(
                            'Fingerprint lagayein\nYa boliye "Drishti Kholo"',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                            textAlign: TextAlign.center,
                          ).animate(delay: 150.ms).fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.xl),

                          // Wake phrase indicator
                          _WakePhraseChip()
                              .animate(delay: 300.ms)
                              .fadeIn(duration: 400.ms),

                          const Spacer(),

                          // Face ID option
                          if (_showFaceId)
                            Semantics(
                              label: 'Use Face ID to login',
                              child: OutlinedButton.icon(
                                onPressed: () => _authenticate(useFace: true),
                                icon: const Icon(Icons.face_rounded,
                                    color: AppColors.saffron),
                                label: const Text('Face ID se Login',
                                    style: TextStyle(color: AppColors.white)),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(
                                      double.infinity, AppSizes.minTouchTarget),
                                  side: const BorderSide(
                                      color: AppColors.navyLight),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSizes.buttonRadius)),
                                ),
                              ),
                            ).animate(delay: 400.ms).fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.md),

                          // Phone login fallback
                          TextButton(
                            onPressed: () {
                              context.read<VoiceService>().speak(
                                    'Phone number se login karte hain.',
                                  );
                              Navigator.pushReplacementNamed(
                                  context, '/login/phone');
                            },
                            child: Text(
                              'Phone number se login karein',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          ),

                          const SizedBox(height: 72),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: DrishtiVoiceBar(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WakePhraseChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg, vertical: AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.saffron.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic_rounded, color: AppColors.saffron, size: 18),
          const SizedBox(width: AppSizes.sm),
          Text(
            '"Drishti Kholo"',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.saffronLight,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
          duration: 2000.ms,
          color: AppColors.saffronLight.withOpacity(0.3),
        );
  }
}
