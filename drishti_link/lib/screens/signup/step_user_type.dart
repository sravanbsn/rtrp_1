import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/signup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/signup_step_scaffold.dart';

class StepUserTypeScreen extends StatefulWidget {
  const StepUserTypeScreen({super.key});

  @override
  State<StepUserTypeScreen> createState() => _StepUserTypeScreenState();
}

class _StepUserTypeScreenState extends State<StepUserTypeScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();

  static const String _openLine = 'Aap user hain ya guardian?';

  @override
  void initState() {
    super.initState();
    _initAndSpeak();
  }

  Future<void> _initAndSpeak() async {
    await _speech.initialize();
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await context.read<VoiceService>().speak(_openLine);
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    _startListening();
  }

  void _startListening() {
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 8),
      onResult: (result) {
        if (result.finalResult) {
          final w = result.recognizedWords.toLowerCase();
          if (w.contains('user') || w.contains('main user') || w.contains('visually')) {
            _selectType(UserType.user);
          } else if (w.contains('guardian') || w.contains('dekhbhal') ||
              w.contains('caretaker') || w.contains('guard')) {
            _selectType(UserType.guardian);
          }
        }
      },
    );
  }

  Future<void> _selectType(UserType type) async {
    _speech.stop();
    context.read<SignUpNotifier>().selectUserType(type);

    final line = type == UserType.user
        ? 'Aap user hain. Bahut achha!'
        : 'Aap guardian hain. Bahut achha!';
    await context.read<VoiceService>().speak(line);

    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) Navigator.pushReplacementNamed(context, '/signup/otp');
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signup = context.watch<SignUpNotifier>();
    final selected = signup.userType;

    return SignUpStepScaffold(
      currentStep: 2,
      onBack: () => Navigator.pushReplacementNamed(context, '/signup/phone'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.md),
        child: Column(
          children: [
            Text(
              'Aap kaun hain?',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: AppSizes.lg),

            // Two giant cards
            Expanded(
              child: Column(
                children: [
                  // ── User card ─────────────────────────────────────
                  Expanded(
                    child: _TypeCard(
                      icon: Icons.blind_rounded,
                      label: 'Main User Hoon',
                      sublabel: 'Mujhe navigation chahiye',
                      color: AppColors.saffron,
                      isSelected: selected == UserType.user,
                      delay: 100.ms,
                      onTap: () => _selectType(UserType.user),
                    ),
                  ),

                  const SizedBox(height: AppSizes.md),

                  // ── Guardian card ─────────────────────────────────
                  Expanded(
                    child: _TypeCard(
                      icon: Icons.shield_rounded,
                      label: 'Main Guardian Hoon',
                      sublabel: 'Main kisi ki dekhbhal karta/karti hoon',
                      color: const Color(0xFF4A90D9),
                      isSelected: selected == UserType.guardian,
                      delay: 250.ms,
                      onTap: () => _selectType(UserType.guardian),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 80), // voice bar clearance
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final bool isSelected;
  final Duration delay;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.isSelected,
    required this.delay,
    required this.onTap,
  });

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Semantics(
        label: '${widget.label}. ${widget.sublabel}. Tap to select.',
        button: true,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..scale(_pressed ? 0.97 : (widget.isSelected ? 1.02 : 1.0)),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.color.withOpacity(0.15)
                : AppColors.navyCard,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(
              color: widget.isSelected ? widget.color : AppColors.navyLight,
              width: widget.isSelected ? 2.5 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: widget.color.withOpacity(0.25),
                      blurRadius: 24,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(0.2),
                  border: Border.all(
                    color: widget.color.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.color,
                  size: 40,
                ),
              ),

              const SizedBox(height: AppSizes.md),

              Text(
                widget.label,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: widget.isSelected ? widget.color : AppColors.white,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSizes.sm),

              Text(
                widget.sublabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),

              if (widget.isSelected) ...[
                const SizedBox(height: AppSizes.md),
                Icon(Icons.check_circle_rounded, color: widget.color, size: 28)
                    .animate()
                    .scale(begin: const Offset(0, 0), end: const Offset(1, 1))
                    .fadeIn(duration: 300.ms),
              ],
            ],
          ),
        )
            .animate(delay: widget.delay)
            .fadeIn(duration: 500.ms)
            .slideY(begin: 0.2, end: 0),
      ),
    );
  }
}
