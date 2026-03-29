import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/signup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/signup_step_scaffold.dart';
import '../../widgets/listening_mic_orb.dart';

class StepNameScreen extends StatefulWidget {
  const StepNameScreen({super.key});

  @override
  State<StepNameScreen> createState() => _StepNameScreenState();
}

class _StepNameScreenState extends State<StepNameScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _textCtrl = TextEditingController();
  bool _speechAvailable = false;
  bool _showTypeField = false;

  static const String _openLine = 'Pehle mujhe aapka naam batayein.';

  @override
  void initState() {
    super.initState();
    _initAndSpeak();
  }

  Future<void> _initAndSpeak() async {
    _speechAvailable = await _speech.initialize();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await context.read<VoiceService>().speak(_openLine);
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    _startListening();
  }

  void _startListening() {
    if (!_speechAvailable) return;
    final signup = context.read<SignUpNotifier>();
    if (signup.nameStatus == StepStatus.confirming) return;

    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _handleSpokenName(result.recognizedWords);
        }
      },
    );
  }

  Future<void> _handleSpokenName(String spoken) async {
    // Voice command aliases
    final lower = spoken.toLowerCase();
    if (_isConfirmWord(lower)) {
      _confirmName();
      return;
    }
    if (_isDenyWord(lower)) {
      _retryName();
      return;
    }

    final signup = context.read<SignUpNotifier>();
    signup.setPendingName(spoken);

    final confirmLine = 'Aapka naam hai ${signup.pendingName}. Sahi hai?';
    await context.read<VoiceService>().speak(confirmLine);

    // Keep listening for confirmation
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 6),
      onResult: (r) {
        if (r.finalResult) {
          final w = r.recognizedWords.toLowerCase();
          if (_isConfirmWord(w)) _confirmName();
          if (_isDenyWord(w)) _retryName();
        }
      },
    );
  }

  bool _isConfirmWord(String w) =>
      w.contains('haan') ||
      w.contains('han') ||
      w.contains('yes') ||
      w.contains('correct') ||
      w.contains('sahi');

  bool _isDenyWord(String w) =>
      w.contains('nahi') ||
      w.contains('no') ||
      w.contains('nope') ||
      w.contains('wrong') ||
      w.contains('galat');

  void _confirmName() {
    context.read<SignUpNotifier>().confirmName();
    context.read<VoiceService>().speak('Bahut achha! Ab aage chalte hain.');
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/signup/phone');
    });
  }

  void _retryName() {
    context.read<SignUpNotifier>().rejectName();
    context.read<VoiceService>().speak('Koi baat nahi. Dobara boliye.');
    Future.delayed(const Duration(milliseconds: 1500), _startListening);
  }

  void _submitTyped() {
    final typed = _textCtrl.text.trim();
    if (typed.isEmpty) return;
    _handleSpokenName(typed);
  }

  @override
  void dispose() {
    _speech.stop();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signup = context.watch<SignUpNotifier>();
    final isConfirming = signup.nameStatus == StepStatus.confirming;

    return SignUpStepScaffold(
      currentStep: 0,
      onBack: () => Navigator.pop(context),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        child: Column(
          children: [
            const Spacer(flex: 1),

            // ── Drishti prompt ────────────────────────────────────
            Text(
              isConfirming ? 'Sahi hai?' : 'Aapka naam?',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: AppSizes.xl),

            // ── Mic orb ───────────────────────────────────────────
            ListeningMicOrb(
              state: isConfirming
                  ? ListeningOrbState.confirming
                  : ListeningOrbState.listening,
              onTap: isConfirming ? null : _startListening,
            )
                .animate()
                .fadeIn(duration: 600.ms, delay: 200.ms)
                .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),

            const SizedBox(height: AppSizes.xl),

            // ── Spoken/typed name display ─────────────────────────
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: signup.pendingName.isNotEmpty
                  ? _NameDisplay(name: signup.pendingName)
                  : const SizedBox(height: 64),
            ),

            // ── Confirm / retry buttons (confirming state) ─────────
            if (isConfirming) ...[
              const SizedBox(height: AppSizes.xl),
              _ConfirmRow(
                onConfirm: _confirmName,
                onRetry: _retryName,
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0),
            ],

            const Spacer(flex: 2),

            // ── Type instead ──────────────────────────────────────
            if (!isConfirming)
              _TypeInsteadSection(
                controller: _textCtrl,
                isVisible: _showTypeField,
                onToggle: () =>
                    setState(() => _showTypeField = !_showTypeField),
                onSubmit: _submitTyped,
              ),

            const SizedBox(height: 80), // voice bar clearance
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _NameDisplay extends StatelessWidget {
  final String name;
  const _NameDisplay({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.saffron.withOpacity(0.4)),
      ),
      child: Text(
        name,
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: AppColors.saffronLight,
            ),
        textAlign: TextAlign.center,
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.9, 0.9));
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
        // ✗ Retry
        Expanded(
          child: Semantics(
            label: 'Wrong name. Tap or say "Nahi" to retry.',
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.close_rounded,
                  color: AppColors.textSecondary),
              label: Text(
                'Nahi',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSizes.minTouchTarget),
                side: const BorderSide(color: AppColors.navyLight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        // ✓ Confirm
        Expanded(
          flex: 2,
          child: Semantics(
            label: 'Correct name. Tap or say "Haan" to confirm.',
            child: ElevatedButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check_rounded, color: AppColors.navyDeep),
              label: const Text('Haan, Sahi Hai'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, AppSizes.minTouchTarget),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypeInsteadSection extends StatelessWidget {
  final TextEditingController controller;
  final bool isVisible;
  final VoidCallback onToggle;
  final VoidCallback onSubmit;

  const _TypeInsteadSection({
    required this.controller,
    required this.isVisible,
    required this.onToggle,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: onToggle,
          child: Text(
            isVisible ? 'Voice se bolein' : 'Type karein',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.textMuted,
                ),
          ),
        ),
        if (isVisible)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Apna naam likhein...',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.navyCard,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSizes.buttonRadius),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Semantics(
                label: 'Submit name',
                child: IconButton(
                  onPressed: onSubmit,
                  icon: const Icon(Icons.arrow_forward_rounded,
                      color: AppColors.saffron),
                  iconSize: 32,
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms),
      ],
    );
  }
}
