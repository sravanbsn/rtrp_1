import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/setup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/setup_scaffold.dart';

class SetupLocationScreen extends StatefulWidget {
  const SetupLocationScreen({super.key});

  @override
  State<SetupLocationScreen> createState() => _SetupLocationScreenState();
}

class _SetupLocationScreenState extends State<SetupLocationScreen> {
  bool _loading = false;
  bool _denied = false;

  static const _openLine =
      'GPS se main aapke guardian ko batati hoon aap kahan hain. '
      'Safe rehne ke liye zaroori hai.';

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) context.read<VoiceService>().speak(_openLine);
    });
  }

  Future<void> _requestLocation() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    final status = await Permission.location.request();
    if (!mounted) return;
    final granted = status.isGranted;
    context.read<SetupNotifier>().setLocationGranted(granted);
    setState(() => _loading = false);

    if (granted) {
      await context.read<VoiceService>().speak('GPS on ho gaya. Bahut acha!');
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pushReplacementNamed(context, '/setup/guardian');
    } else {
      setState(() => _denied = true);
      await context.read<VoiceService>().speak(
            'Koi baat nahi. Settings mein baad mein de sakte hain.',
          );
    }
  }

  Future<void> _skip() async {
    await context.read<VoiceService>().speak('Theek hai, aage chalte hain.');
    if (mounted) Navigator.pushReplacementNamed(context, '/setup/guardian');
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      step: SetupStep.location,
      title: 'Location Permission',
      subtitle: 'Guardian aapki safety ke liye aapko track kar sake.',
      icon: _LocationIcon(denied: _denied),
      body: Column(
        children: [
          if (_denied) ...[
            const _DeniedBanner(
                    message:
                        'Koi baat nahi. Settings mein baad mein de sakte hain.')
                .animate()
                .fadeIn(duration: 300.ms)
                .shake(hz: 3, offset: const Offset(4, 0)),
            const SizedBox(height: AppSizes.lg),
          ],
          SetupPermissionButtons(
            onAllow: _requestLocation,
            onSkip: _skip,
            loading: _loading,
          ),
        ],
      ),
    );
  }
}

class _LocationIcon extends StatelessWidget {
  final bool denied;
  const _LocationIcon({this.denied = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: denied
              ? [
                  AppColors.hazardRed.withValues(alpha: 0.3),
                  AppColors.hazardRed.withValues(alpha: 0.1),
                ]
              : [
                  const Color(0xFF66B2FF).withValues(alpha: 0.25),
                  const Color(0xFF3399FF).withValues(alpha: 0.08),
                ],
        ),
        border: Border.all(
          color: denied
              ? AppColors.hazardRed.withValues(alpha: 0.5)
              : const Color(0xFF66B2FF).withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Icon(
        denied ? Icons.location_off_rounded : Icons.location_on_rounded,
        size: 56,
        color: denied ? AppColors.hazardRed : const Color(0xFF66B2FF),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
          end: denied ? 1.0 : 1.1,
          duration: 1600.ms,
          curve: Curves.easeInOut,
        );
  }
}

class _DeniedBanner extends StatelessWidget {
  final String message;
  const _DeniedBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.hazardRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(color: AppColors.hazardRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.hazardRed, size: 20),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.hazardRed)),
          ),
        ],
      ),
    );
  }
}
