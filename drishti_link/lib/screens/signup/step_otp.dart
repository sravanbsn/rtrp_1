import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/signup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/signup_step_scaffold.dart';
import '../../widgets/listening_mic_orb.dart';

class StepOtpScreen extends StatefulWidget {
  const StepOtpScreen({super.key});

  @override
  State<StepOtpScreen> createState() => _StepOtpScreenState();
}

class _StepOtpScreenState extends State<StepOtpScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  static const String _openLine =
      'Ek code aaya hai. Apna OTP boliye.';

  @override
  void initState() {
    super.initState();
    _initAndSpeak();
  }

  Future<void> _initAndSpeak() async {
    _speechAvailable = await _speech.initialize();
    // Reset OTP
    context.read<SignUpNotifier>().setOtp('');

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await context.read<VoiceService>().speak(_openLine);
    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;
    _startListening();
  }

  void _startListening() {
    if (!_speechAvailable) return;
    final signup = context.read<SignUpNotifier>();
    if (signup.otpStatus == StepStatus.loading ||
        signup.otpStatus == StepStatus.done) {
      return;
    }

    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        if (result.finalResult) {
          _handleSpokenOtp(result.recognizedWords);
        }
      },
    );
  }

  Future<void> _handleSpokenOtp(String spoken) async {
    final digits = _extractDigits(spoken);
    if (digits.isEmpty) {
      await context.read<VoiceService>().speak(
        'Woh sahi nahi laga. Dobara boliye?',
      );
      Future.delayed(const Duration(milliseconds: 2000), _startListening);
      return;
    }

    final signup = context.read<SignUpNotifier>();
    signup.setOtp(digits);

    if (signup.otp.length == 6) {
      _verifyOtp();
    } else {
      await context.read<VoiceService>().speak(
        '${signup.otp.length} digits mili hain. Poora 6 digit boliye.',
      );
      Future.delayed(const Duration(milliseconds: 2000), _startListening);
    }
  }

  String _extractDigits(String spoken) {
    final Map<String, String> wordMap = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'shunya': '0', 'ek': '1', 'do': '2', 'teen': '3', 'chaar': '4',
      'paanch': '5', 'chheh': '6', 'saat': '7', 'aath': '8', 'nau': '9',
    };
    var s = spoken.toLowerCase();
    wordMap.forEach((k, v) => s = s.replaceAll(k, v));
    return s.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _verifyOtp() async {
    _speech.stop();
    final signup = context.read<SignUpNotifier>();
    signup.setOtpStatus(StepStatus.loading);
    await context.read<VoiceService>().speak('Check kar rahi hoon...');

    // Simulate verification delay
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    signup.setOtpStatus(StepStatus.done);
    await context.read<VoiceService>().speak(
      'Shukriya! Aapka account ban gaya.',
    );
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signup = context.watch<SignUpNotifier>();
    final status = signup.otpStatus;
    final otp = signup.otp;

    return SignUpStepScaffold(
      currentStep: 3,
      onBack: () => Navigator.pushReplacementNamed(context, '/signup/usertype'),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        child: Column(
          children: [
            const Spacer(flex: 1),

            // Prompt
            Text(
              status == StepStatus.loading
                  ? 'Check kar rahi hoon...'
                  : status == StepStatus.done
                      ? 'Shukriya!'
                      : 'OTP boliye',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: AppSizes.xl),

            // Mic orb
            ListeningMicOrb(
              state: status == StepStatus.loading
                  ? ListeningOrbState.loading
                  : status == StepStatus.done
                      ? ListeningOrbState.done
                      : ListeningOrbState.listening,
              onTap: (status == StepStatus.listening) ? _startListening : null,
            )
                .animate()
                .fadeIn(duration: 600.ms, delay: 200.ms)
                .scale(begin: const Offset(0.85, 0.85)),

            const SizedBox(height: AppSizes.xl),

            // OTP boxes
            _OtpBoxRow(otp: otp)
                .animate()
                .fadeIn(duration: 500.ms, delay: 300.ms),

            const Spacer(flex: 1),

            // Success celebration
            if (status == StepStatus.done)
              _CelebrationWidget()
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.5, 0.5)),

            const Spacer(flex: 1),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6-box OTP row
// ─────────────────────────────────────────────────────────────────────────────

class _OtpBoxRow extends StatelessWidget {
  final String otp;
  const _OtpBoxRow({required this.otp});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final hasDigit = i < otp.length;
        final digit = hasDigit ? otp[i] : '';
        final isNext = i == otp.length;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: AnimatedContainer(
            duration: AppDurations.medium,
            curve: Curves.easeOut,
            width: 44,
            height: 56,
            decoration: BoxDecoration(
              color: hasDigit
                  ? AppColors.saffron.withOpacity(0.15)
                  : AppColors.navyCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isNext
                    ? AppColors.saffron
                    : hasDigit
                        ? AppColors.saffron.withOpacity(0.6)
                        : AppColors.navyLight,
                width: isNext ? 2 : 1.5,
              ),
            ),
            child: Center(
              child: Text(
                digit,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.saffronLight,
                  fontSize: 24,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Celebration widget — confetti-like particles
// ─────────────────────────────────────────────────────────────────────────────

class _CelebrationWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Confetti dots
          ...List.generate(12, (i) {
            final angle = (i / 12) * 2 * math.pi;
            const radius = 70.0;
            final colors = [
              AppColors.saffron,
              AppColors.saffronLight,
              AppColors.safeGreen,
              Colors.white,
            ];
            return Positioned(
              left: 110 + radius * math.cos(angle),
              top: 60 + radius * math.sin(angle),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors[i % colors.length],
                  shape: BoxShape.circle,
                ),
              )
                  .animate(delay: Duration(milliseconds: i * 60))
                  .scale(begin: const Offset(0, 0), end: const Offset(1, 1))
                  .fadeIn(duration: 400.ms),
            );
          }),

          // Center text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.safeGreen,
                size: 48,
              ),
              const SizedBox(height: 8),
              Text(
                'Account ban gaya! 🎉',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.safeGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
