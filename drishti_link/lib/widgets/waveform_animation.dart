import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';

/// Animated audio waveform at the bottom of the splash screen.
/// 9 bars with staggered height animation for a breathing wave feel.
class WaveformAnimation extends StatelessWidget {
  const WaveformAnimation({super.key});

  static const int _barCount = 9;
  static const double _maxHeight = 32.0;
  static const double _minHeight = 6.0;
  static const double _barWidth = 4.0;
  static const double _barGap = 6.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _maxHeight + 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (i) {
          // Each bar gets a unique height target and delay for organic feel
          final heightFraction = _barHeights[i];
          final delayMs = i * 80;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: _barGap / 2),
            child: _WaveBar(
              maxHeight: _maxHeight * heightFraction,
              minHeight: _minHeight,
              width: _barWidth,
              delay: Duration(milliseconds: delayMs),
            ),
          );
        }),
      ),
    );
  }

  static const List<double> _barHeights = [
    0.40, 0.65, 0.85, 1.0, 0.75, 1.0, 0.85, 0.60, 0.35,
  ];
}

class _WaveBar extends StatelessWidget {
  final double maxHeight;
  final double minHeight;
  final double width;
  final Duration delay;

  const _WaveBar({
    required this.maxHeight,
    required this.minHeight,
    required this.width,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: maxHeight,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.saffronLight, AppColors.saffron],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(width / 2),
      ),
    )
        .animate(
          delay: delay,
          onPlay: (c) => c.repeat(reverse: true),
        )
        .scaleY(
          begin: minHeight / maxHeight,
          end: 1.0,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
          alignment: Alignment.center,
        );
  }
}
