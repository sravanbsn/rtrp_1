import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import '../services/setup_service.dart';

/// Shared scaffold for all 5 setup screens.
/// Provides the progress bar, title, and consistent layout.
class SetupScaffold extends StatelessWidget {
  final SetupStep step;
  final String title;
  final String subtitle;
  final Widget icon;
  final Widget body;

  const SetupScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final totalSteps = SetupStep.values.length;
    final stepIndex = SetupStep.values.indexOf(step) + 1;
    final progress = stepIndex / totalSteps;

    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress bar ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg, AppSizes.md, AppSizes.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Step $stepIndex of $totalSteps',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                      ),
                      Text(
                        _stepLabel(step),
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.saffron,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: AppColors.navyLight,
                      valueColor: const AlwaysStoppedAnimation(AppColors.saffron),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 400.ms),
                ],
              ),
            ),

            // ── Icon zone ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSizes.xl),
              child: icon
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scaleXY(begin: 0.7, end: 1.0, curve: Curves.elasticOut),
            ),

            // ── Card panel ────────────────────────────────────────
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
                      AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineLarge)
                          .animate(delay: 150.ms)
                          .fadeIn(duration: 400.ms),
                      const SizedBox(height: AppSizes.sm),
                      Text(subtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: AppColors.textMuted))
                          .animate(delay: 250.ms)
                          .fadeIn(duration: 400.ms),
                      const SizedBox(height: AppSizes.xl),
                      body
                          .animate(delay: 350.ms)
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.08, end: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stepLabel(SetupStep s) {
    switch (s) {
      case SetupStep.camera:
        return 'Camera';
      case SetupStep.location:
        return 'Location';
      case SetupStep.guardian:
        return 'Guardian';
      case SetupStep.language:
        return 'Language';
      case SetupStep.haptic:
        return 'Haptic';
    }
  }
}

/// Saffron "allow" button + ghost "skip" button — used in permission screens.
class SetupPermissionButtons extends StatelessWidget {
  final String allowLabel;
  final String skipLabel;
  final VoidCallback onAllow;
  final VoidCallback onSkip;
  final bool loading;

  const SetupPermissionButtons({
    super.key,
    this.allowLabel = 'Haan, de do',
    this.skipLabel = 'Baad mein',
    required this.onAllow,
    required this.onSkip,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          label: allowLabel,
          child: ElevatedButton(
            onPressed: loading ? null : onAllow,
            style: ElevatedButton.styleFrom(
              minimumSize:
                  const Size(double.infinity, AppSizes.minTouchTarget),
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.navyDeep),
                  )
                : Text(allowLabel),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Semantics(
          label: skipLabel,
          child: OutlinedButton(
            onPressed: loading ? null : onSkip,
            style: OutlinedButton.styleFrom(
              minimumSize:
                  const Size(double.infinity, AppSizes.minTouchTarget),
              side: const BorderSide(color: AppColors.navyLight),
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSizes.buttonRadius)),
            ),
            child: Text(skipLabel,
                style: const TextStyle(color: AppColors.textMuted)),
          ),
        ),
      ],
    );
  }
}
