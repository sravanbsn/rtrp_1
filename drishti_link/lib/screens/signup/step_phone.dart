import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/signup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/signup_step_scaffold.dart';
import '../../widgets/listening_mic_orb.dart';

class StepPhoneScreen extends StatefulWidget {
  const StepPhoneScreen({super.key});

  @override
  State<StepPhoneScreen> createState() => _StepPhoneScreenState();
}

class _StepPhoneScreenState extends State<StepPhoneScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  static const String _openLine = 'Ab apna phone number boliye.';

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
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    _startListening();
  }

  void _startListening() {
    if (!_speechAvailable) return;
    final signup = context.read<SignUpNotifier>();
    if (signup.phoneStatus == StepStatus.confirming) return;

    signup.clearPhone();

    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        if (result.finalResult) {
          _handleSpokenPhone(result.recognizedWords);
        }
      },
    );
  }

  Future<void> _handleSpokenPhone(String spoken) async {
    // Extract digits from spoken words
    final digits = _wordsToDigits(spoken);
    if (digits.length < 10) {
      await context.read<VoiceService>().speak(
        'Woh sahi nahi laga. Dobara boliye apna 10 digit number.',
      );
      Future.delayed(const Duration(milliseconds: 2500), _startListening);
      return;
    }

    final phone10 = digits.substring(0, 10);
    context.read<SignUpNotifier>().setPendingPhone(phone10);

    // Read back with gaps for clarity
    final readback = phone10.split('').join(' ');
    await context.read<VoiceService>().speak(
      'Aapka number hai $readback. Sahi hai?',
    );

    // Listen for confirmation
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 6),
      onResult: (r) {
        if (r.finalResult) {
          final w = r.recognizedWords.toLowerCase();
          if (_isYes(w)) _confirmPhone();
          if (_isNo(w)) _retryPhone();
        }
      },
    );
  }

  /// Converts spoken number words and digits to a digit string
  String _wordsToDigits(String spoken) {
    final Map<String, String> wordMap = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'shunya': '0', 'ek': '1', 'do': '2', 'teen': '3', 'chaar': '4',
      'paanch': '5', 'chheh': '6', 'saat': '7', 'aath': '8', 'nau': '9',
    };
    var result = spoken.toLowerCase();
    wordMap.forEach((word, digit) {
      result = result.replaceAll(word, digit);
    });
    return result.replaceAll(RegExp(r'\D'), '');
  }

  bool _isYes(String w) =>
      w.contains('haan') || w.contains('han') || w.contains('yes') ||
      w.contains('sahi') || w.contains('correct');

  bool _isNo(String w) =>
      w.contains('nahi') || w.contains('no') || w.contains('galat') ||
      w.contains('wrong');

  void _confirmPhone() {
    context.read<SignUpNotifier>().confirmPhone();
    context.read<VoiceService>().speak('Aage chalte hain!');
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/signup/usertype');
    });
  }

  void _retryPhone() {
    context.read<VoiceService>().speak('Koi baat nahi. Dobara boliye.');
    Future.delayed(const Duration(milliseconds: 1800), _startListening);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signup = context.watch<SignUpNotifier>();
    final isConfirming = signup.phoneStatus == StepStatus.confirming;
    final digits = signup.pendingPhone;

    return SignUpStepScaffold(
      currentStep: 1,
      onBack: () => Navigator.pushReplacementNamed(context, '/signup/name'),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        child: Column(
          children: [
            const Spacer(flex: 1),

            // Prompt
            Text(
              isConfirming ? 'Sahi hai?' : 'Phone number?',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: AppSizes.xl),

            // Mic orb
            ListeningMicOrb(
              state: isConfirming
                  ? ListeningOrbState.confirming
                  : ListeningOrbState.listening,
              onTap: isConfirming ? null : _startListening,
            )
                .animate()
                .fadeIn(duration: 600.ms, delay: 200.ms)
                .scale(begin: const Offset(0.85, 0.85)),

            const SizedBox(height: AppSizes.xl),

            // Live digit display
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: digits.isNotEmpty
                  ? _PhoneDisplay(digits: digits)
                  : SizedBox(
                      height: 80,
                      child: Center(
                        child: Text(
                          isConfirming ? '' : 'Boliye...',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
            ),

            // Confirm row
            if (isConfirming) ...[
              const SizedBox(height: AppSizes.xl),
              _ConfirmRow(
                onConfirm: _confirmPhone,
                onRetry: _retryPhone,
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.3, end: 0),
            ],

            const Spacer(flex: 2),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _PhoneDisplay extends StatelessWidget {
  final String digits;
  const _PhoneDisplay({required this.digits});

  @override
  Widget build(BuildContext context) {
    // Format: XXXXX XXXXX
    final formatted = digits.length > 5
        ? '${digits.substring(0, 5)} ${digits.substring(5)}'
        : digits;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.saffron.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+91  ',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          Text(
            formatted,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: AppColors.saffronLight,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }
}

class _ConfirmRow extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onRetry;
  const _ConfirmRow({required this.onConfirm, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Wrong number. Say "Nahi" or tap to retry.',
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
              label: Text('Nahi', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.textSecondary)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSizes.minTouchTarget),
                side: const BorderSide(color: AppColors.navyLight),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.buttonRadius)),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          flex: 2,
          child: Semantics(
            label: 'Correct number. Say "Haan" or tap to confirm.',
            child: ElevatedButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check_rounded, color: AppColors.navyDeep),
              label: const Text('Haan, Sahi Hai'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, AppSizes.minTouchTarget)),
            ),
          ),
        ),
      ],
    );
  }
}
