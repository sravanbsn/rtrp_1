import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';

/// Persistent bottom bar — always visible, always listening.
/// Tapping it re-speaks the current Drishti line.
class DrishtiVoiceBar extends StatelessWidget {
  const DrishtiVoiceBar({super.key});

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceService>();

    return Semantics(
      label: 'Drishti voice bar. Tap to repeat what Drishti said.',
      child: GestureDetector(
        onTap: () => voice.repeat(),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.navyCard.withOpacity(0.97),
            border: const Border(
              top: BorderSide(color: AppColors.navyLight, width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            child: Row(
              children: [
                // Mic icon — pulses when Drishti is speaking
                _MicIcon(isSpeaking: voice.isSpeaking),

                const SizedBox(width: AppSizes.sm),

                // Status text
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppDurations.fast,
                    child: Text(
                      voice.isSpeaking
                          ? 'Drishti bol rahi hai...'
                          : 'Drishti sun rahi hai...',
                      key: ValueKey(voice.isSpeaking),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: voice.isSpeaking
                                ? AppColors.saffronLight
                                : AppColors.textMuted,
                            fontSize: 13,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                // Repeat hint
                const Icon(
                  Icons.replay_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MicIcon extends StatelessWidget {
  final bool isSpeaking;
  const _MicIcon({required this.isSpeaking});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isSpeaking ? AppColors.saffron : AppColors.navyLight,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isSpeaking ? Icons.volume_up_rounded : Icons.mic_rounded,
        color: isSpeaking ? AppColors.navyDeep : AppColors.saffron,
        size: 16,
      ),
    )
        .animate(
          onPlay: (c) => isSpeaking ? c.repeat(reverse: true) : c.stop(),
        )
        .scaleXY(
          end: isSpeaking ? 1.15 : 1.0,
          duration: 600.ms,
          curve: Curves.easeInOut,
        );
  }
}
