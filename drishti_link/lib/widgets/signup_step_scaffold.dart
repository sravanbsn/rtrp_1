import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';
import 'drishti_voice_bar.dart';

/// Shared scaffold for every sign-up step.
/// Provides: progress dots, back arrow, voice bar, and body slot.
class SignUpStepScaffold extends StatelessWidget {
  final int currentStep; // 0-based, 0..3
  final int totalSteps;
  final Widget body;
  final VoidCallback? onBack;

  const SignUpStepScaffold({
    super.key,
    required this.currentStep,
    required this.body,
    this.onBack,
    this.totalSteps = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ── Top bar ────────────────────────────────────────
                _TopBar(
                  currentStep: currentStep,
                  totalSteps: totalSteps,
                  onBack: onBack,
                ),

                // ── Step body ──────────────────────────────────────
                Expanded(child: body),
              ],
            ),

            // ── Persistent voice bar ───────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// Top bar: back arrow + progress dots
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onBack;

  const _TopBar({
    required this.currentStep,
    required this.totalSteps,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.sm, AppSizes.md, AppSizes.md, AppSizes.sm),
      child: Row(
        children: [
          // Back arrow
          Semantics(
            label: 'Go back. Say "Pichle step" to activate.',
            child: _BackButton(onBack: onBack ?? () => Navigator.pop(context)),
          ),

          // Progress dots (centered)
          Expanded(
            child: Center(
              child: _ProgressDots(
                  currentStep: currentStep, totalSteps: totalSteps),
            ),
          ),

          // Spacer to balance back button
          const SizedBox(width: AppSizes.minTouchTarget),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onBack;
  const _BackButton({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.read<VoiceService>().speak('Pichle step pe jaayein?');
        Future.delayed(const Duration(milliseconds: 1200), onBack);
      },
      child: Container(
        width: AppSizes.minTouchTarget,
        height: AppSizes.minTouchTarget,
        alignment: Alignment.center,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.navyCard,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.navyLight),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textSecondary,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _ProgressDots({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalSteps, (i) {
        final isActive = i == currentStep;
        final isDone = i < currentStep;
        return AnimatedContainer(
          duration: AppDurations.medium,
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.saffron
                : isDone
                    ? AppColors.saffron.withOpacity(0.5)
                    : AppColors.navyCard,
            borderRadius: BorderRadius.circular(4),
            border: isDone || isActive
                ? null
                : Border.all(color: AppColors.navyLight),
          ),
        );
      }),
    );
  }
}
