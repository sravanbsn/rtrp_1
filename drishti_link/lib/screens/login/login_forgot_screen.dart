import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/voice_service.dart';
import '../../widgets/drishti_voice_bar.dart';

class LoginForgotScreen extends StatefulWidget {
  const LoginForgotScreen({super.key});

  @override
  State<LoginForgotScreen> createState() => _LoginForgotScreenState();
}

class _LoginForgotScreenState extends State<LoginForgotScreen> {
  bool _guardianRequested = false;
  bool _isLoading = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  static const String _openLine =
      'Koi baat nahi. Kya guardian help kar sakta hai?';

  @override
  void initState() {
    super.initState();
    _initAndSpeak();
  }

  Future<void> _initAndSpeak() async {
    _speechAvailable = await _speech.initialize();
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await context.read<VoiceService>().speak(_openLine);
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    _startListening();
  }

  /// Listens for guardian-related voice commands hands-free.
  void _startListening() {
    if (!_speechAvailable || !mounted || _guardianRequested || _isLoading) return;
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
        if (!result.finalResult) return;
        final words = result.recognizedWords.toLowerCase();

        // "Guardian bulao" / "haan" / "help" → call guardian
        if (words.contains('guardian') ||
            words.contains('bulao') ||
            words.contains('haan') ||
            words.contains('han') ||
            words.contains('yes') ||
            words.contains('help') ||
            words.contains('madad')) {
          _requestGuardian();
        }
        // "Nahi" / "number" → try a different phone number
        else if (words.contains('nahi') ||
            words.contains('number') ||
            words.contains('doosra') ||
            words.contains('no')) {
          _tryPhoneInstead();
        }
        // "Support" → contact support
        else if (words.contains('support') || words.contains('sampark')) {
          _contactSupport();
        }
      },
    );
  }

  Future<void> _requestGuardian() async {
    if (_isLoading || _guardianRequested) return;
    _speech.stop();
    setState(() => _isLoading = true);
    await context.read<VoiceService>().speak(
          'Guardian ko notification bhej rahi hoon. Unse madad maangein.',
        );
    // TODO: real guardian notification API call
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _guardianRequested = true;
    });
    await context.read<VoiceService>().speak(
          'Guardian ko message bhej diya. Woh jald aapki madad karenge.',
        );
  }

  Future<void> _tryPhoneInstead() async {
    _speech.stop();
    await context.read<VoiceService>().speak(
          'Chaliye, doosra number try karte hain.',
        );
    if (mounted) Navigator.pushReplacementNamed(context, '/login/phone');
  }

  Future<void> _contactSupport() async {
    _speech.stop();
    await context.read<VoiceService>().speak(
          'Support team se sampark kar rahe hain.',
        );
    // TODO: open support link / mailto
    if (mounted) _startListening();
  }

  @override
  void dispose() {
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
                // ── TOP 38% ─────────────────────────────────────────
                SizedBox(
                  height: size.height * 0.38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Radial glow
                      Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              (_guardianRequested
                                      ? AppColors.safeGreen
                                      : AppColors.saffron)
                                  .withOpacity(0.15),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),

                      // Guardian icon orb
                      _GuardianOrb(
                        requested: _guardianRequested,
                        loading: _isLoading,
                      ).animate().fadeIn(duration: 600.ms),
                    ],
                  ),
                ),

                // ── BOTTOM panel ─────────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: AppColors.navyMid,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                          AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _guardianRequested
                                ? 'Guardian Ko Bataya! ✓'
                                : 'Madad Chahiye?',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ).animate().fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.sm),

                          Text(
                            _guardianRequested
                                ? 'Aapka guardian jald aapki madad karega.'
                                : 'Aapka guardian aapke account mein login karne mein help kar sakta hai.',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                          ).animate(delay: 100.ms).fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.xl),

                          if (!_guardianRequested) ...[
                            // ── Listening chip ───────────────────────
                            Center(
                              child: _VoiceCommandChip(),
                            )
                                .animate(delay: 150.ms)
                                .fadeIn(duration: 400.ms),

                            const SizedBox(height: AppSizes.lg),

                            // Guardian help button
                            Semantics(
                              label:
                                  'Contact guardian for help. Say "Guardian bulao" to activate.',
                              child: ElevatedButton.icon(
                                onPressed: _isLoading ? null : _requestGuardian,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.navyDeep,
                                        ),
                                      )
                                    : const Icon(Icons.shield_rounded,
                                        color: AppColors.navyDeep),
                                label: Text(_isLoading
                                    ? 'Message bhej rahe hain...'
                                    : 'Guardian Se Madad Maango'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(
                                      double.infinity, AppSizes.minTouchTarget),
                                ),
                              ),
                            ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

                            const SizedBox(height: AppSizes.md),

                            // Try different number
                            Semantics(
                              label: 'Try a different phone number',
                              child: OutlinedButton.icon(
                                onPressed: _tryPhoneInstead,
                                icon: const Icon(Icons.phone_rounded,
                                    color: AppColors.saffron),
                                label: const Text('Doosra Number Try Karein',
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
                            ).animate(delay: 300.ms).fadeIn(duration: 400.ms),

                            const SizedBox(height: AppSizes.md),

                            // Support
                            Center(
                              child: TextButton(
                                onPressed: _contactSupport,
                                child: Text(
                                  'Support se sampark karein',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                              ),
                            ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
                          ] else ...[
                            // Success state — guardian notified
                            _GuardianSuccessCard()
                                .animate()
                                .fadeIn(duration: 500.ms)
                                .slideY(begin: 0.2, end: 0),

                            const SizedBox(height: AppSizes.xl),

                            TextButton.icon(
                              onPressed: _tryPhoneInstead,
                              icon: const Icon(Icons.arrow_back_rounded,
                                  color: AppColors.textMuted),
                              label: Text(
                                'Dobara try karein',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppColors.textMuted),
                              ),
                            ),
                          ],

                          const SizedBox(height: 80), // voice bar clearance
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const Positioned(
              bottom: 0, left: 0, right: 0,
              child: DrishtiVoiceBar(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// Chip that shows the user which voice commands are available.
class _VoiceCommandChip extends StatelessWidget {
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
            '"Guardian bulao" ya "Doosra number"',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.saffronLight,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(
          duration: 2000.ms,
          color: AppColors.saffronLight.withOpacity(0.3),
        );
  }
}

class _GuardianOrb extends StatelessWidget {
  final bool requested;
  final bool loading;
  const _GuardianOrb({required this.requested, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: requested
              ? [
                  const Color(0xFF66FFB0),
                  AppColors.safeGreen,
                  const Color(0xFF22BB66),
                ]
              : [
                  AppColors.saffronLight,
                  AppColors.saffron,
                  AppColors.saffronDark,
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: (requested ? AppColors.safeGreen : AppColors.saffron)
                .withOpacity(0.5),
            blurRadius: 36,
            spreadRadius: 8,
          ),
        ],
      ),
      child: loading
          ? const CircularProgressIndicator(
              color: AppColors.navyDeep, strokeWidth: 3)
          : Icon(
              requested
                  ? Icons.check_circle_outline_rounded
                  : Icons.person_search_rounded,
              color: AppColors.navyDeep,
              size: 60,
            ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          end: requested ? 1.0 : 1.06,
          duration: 1800.ms,
          curve: Curves.easeInOut,
        );
  }
}

class _GuardianSuccessCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.safeGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.safeGreen.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.shield_rounded,
              color: AppColors.safeGreen, size: 36),
          const SizedBox(height: AppSizes.md),
          Text(
            'Guardian ko message mila!',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.safeGreen,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Woh aapko call ya message karenge aur account recover karne mein help karenge.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
