import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import '../../core/theme.dart';
import '../../services/setup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/setup_scaffold.dart';

class SetupHapticScreen extends StatefulWidget {
  const SetupHapticScreen({super.key});

  @override
  State<SetupHapticScreen> createState() => _SetupHapticScreenState();
}

class _SetupHapticScreenState extends State<SetupHapticScreen> {
  HapticIntensity _intensity = HapticIntensity.medium;
  String? _lastTested; // 'left' | 'right' | 'stop'
  bool _canVibrate = false;

  @override
  void initState() {
    super.initState();
    _checkVibration();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        context.read<VoiceService>().speak(
              'Ab main aapko kuch feel karaati hoon. '
              'Neeche diye buttons dabao aur vibration feel karo.',
            );
      }
    });
  }

  Future<void> _checkVibration() async {
    final has = await Vibration.hasVibrator() ?? false;
    if (mounted) setState(() => _canVibrate = has);
  }

  /// Plays vibration pattern based on side and current intensity.
  Future<void> _vibrate(String side) async {
    setState(() => _lastTested = side);
    final factor = _intensityFactor;

    if (!_canVibrate) {
      // Fallback to HapticFeedback on platforms without Vibration package
      if (side == 'stop') {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
      return;
    }

    switch (side) {
      case 'left':
        // Two short pulses on left side
        await Vibration.vibrate(
          pattern: [0, 80 * factor, 60, 80 * factor],
          intensities: [0, 150, 0, 150],
        );
        break;
      case 'right':
        // Two short pulses offset
        await Vibration.vibrate(
          pattern: [60, 80 * factor, 60, 80 * factor],
          intensities: [0, 150, 0, 150],
        );
        break;
      case 'stop':
        // One long strong pulse
        await Vibration.vibrate(
          duration: 400 * factor,
          amplitude: 255,
        );
        break;
    }

    if (mounted && side == 'stop') {
      await context
          .read<VoiceService>()
          .speak('Theek laga? Ab "Sab theek hai" dabao.');
    }
  }

  int get _intensityFactor {
    switch (_intensity) {
      case HapticIntensity.low:
        return 1;
      case HapticIntensity.medium:
        return 2;
      case HapticIntensity.high:
        return 3;
    }
  }

  void _setIntensity(HapticIntensity v) {
    setState(() => _intensity = v);
    context.read<SetupNotifier>().setHapticIntensity(v);
  }

  Future<void> _finish() async {
    context.read<SetupNotifier>().confirmHaptic();
    await context.read<VoiceService>().speak(
          'Bahut acha! Setup complete ho gaya. Chalo shuru karte hain!',
        );
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      step: SetupStep.haptic,
      title: 'Haptic Test',
      subtitle: 'Vibration feel karo aur intensity set karo.',
      icon: _HapticIcon(tested: _lastTested != null),
      body: Column(
        children: [
          // ── Three test buttons ─────────────────────────────────
          _HapticButton(
            label: '⬅️  Left Warning Test',
            color: const Color(0xFF66B2FF),
            isActive: _lastTested == 'left',
            onTap: () => _vibrate('left'),
          ),
          const SizedBox(height: AppSizes.md),
          _HapticButton(
            label: '➡️  Right Warning Test',
            color: const Color(0xFFB266FF),
            isActive: _lastTested == 'right',
            onTap: () => _vibrate('right'),
          ),
          const SizedBox(height: AppSizes.md),
          _HapticButton(
            label: '🛑  STOP Alert Test',
            color: AppColors.hazardRed,
            isActive: _lastTested == 'stop',
            onTap: () => _vibrate('stop'),
          ),

          const SizedBox(height: AppSizes.xl),

          // ── Intensity slider ───────────────────────────────────
          Text(
            'Intensity',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSizes.sm),
          _IntensitySelector(
            value: _intensity,
            onChanged: _setIntensity,
          ),

          const SizedBox(height: AppSizes.xl),

          // ── Finish button ──────────────────────────────────────
          Semantics(
            label: 'Finish setup. All done.',
            child: ElevatedButton(
              onPressed: _finish,
              style: ElevatedButton.styleFrom(
                minimumSize:
                    const Size(double.infinity, AppSizes.minTouchTarget),
              ),
              child: const Text('Sab Theek Hai, Chalo! 🚀'),
            ),
          ).animate(delay: 600.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _HapticIcon extends StatelessWidget {
  final bool tested;
  const _HapticIcon({this.tested = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.saffronLight.withValues(alpha: 0.25),
            AppColors.saffron.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(
            color: AppColors.saffron.withValues(alpha: 0.5), width: 2),
      ),
      child: Icon(
        tested ? Icons.vibration_rounded : Icons.touch_app_rounded,
        size: 52,
        color: AppColors.saffron,
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(end: 1.09, duration: 1800.ms, curve: Curves.easeInOut);
  }
}

class _HapticButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _HapticButton({
    required this.label,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          width: double.infinity,
          height: AppSizes.minTouchTarget + 8,
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.2)
                : AppColors.navyCard,
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.4),
              width: isActive ? 2.5 : 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isActive ? color : AppColors.textSecondary,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 16,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntensitySelector extends StatelessWidget {
  final HapticIntensity value;
  final ValueChanged<HapticIntensity> onChanged;

  const _IntensitySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = {
      HapticIntensity.low: 'Halka',
      HapticIntensity.medium: 'Theek',
      HapticIntensity.high: 'Tej',
    };

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      ),
      child: Row(
        children: HapticIntensity.values.map((intensity) {
          final isSelected = value == intensity;
          return Expanded(
            child: Semantics(
              label: labels[intensity],
              selected: isSelected,
              child: GestureDetector(
                onTap: () => onChanged(intensity),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.saffron
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppSizes.buttonRadius - 4),
                  ),
                  child: Center(
                    child: Text(
                      labels[intensity]!,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.navyDeep
                            : AppColors.textMuted,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
