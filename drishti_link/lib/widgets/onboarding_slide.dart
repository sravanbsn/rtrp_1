import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';

/// Reusable onboarding slide.
/// Full-height illustration in top 55%, headline + subtext below.
class OnboardingSlide extends StatelessWidget {
  final Widget illustration;
  final String headline;
  final String subtext;

  const OnboardingSlide({
    super.key,
    required this.illustration,
    required this.headline,
    required this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Semantics(
      // Make the entire slide describable for screen readers
      label: '$headline. $subtext',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Illustration area ────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            child: SizedBox(
              height: size.height * 0.52,
              width: double.infinity,
              child: illustration,
            ),
          ),

          // ── Text content ─────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Saffron accent bar
                  Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.saffron,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: -0.3),

                  const SizedBox(height: AppSizes.md),

                  // Headline
                  Text(
                    headline,
                    style: Theme.of(context).textTheme.displayMedium,
                  )
                      .animate(delay: 150.ms)
                      .fadeIn(duration: 500.ms)
                      .slideY(begin: 0.2, end: 0),

                  const SizedBox(height: AppSizes.sm),

                  // Subtext
                  Text(
                    subtext,
                    style: Theme.of(context).textTheme.bodyLarge,
                  )
                      .animate(delay: 300.ms)
                      .fadeIn(duration: 500.ms)
                      .slideY(begin: 0.2, end: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
