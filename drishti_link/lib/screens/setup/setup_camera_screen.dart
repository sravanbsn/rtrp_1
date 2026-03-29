import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/setup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/setup_scaffold.dart';

class SetupCameraScreen extends StatefulWidget {
  const SetupCameraScreen({super.key});

  @override
  State<SetupCameraScreen> createState() => _SetupCameraScreenState();
}

class _SetupCameraScreenState extends State<SetupCameraScreen> {
  bool _loading = false;
  bool _denied = false;

  static const _openLine =
      'Mujhe aapka camera chahiye taaki main raasta dekh sakoon. Theek hai?';

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        context.read<VoiceService>().speak(_openLine);
      }
    });
  }

  Future<void> _requestCamera() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    final status = await Permission.camera.request();
    if (!mounted) return;
    final granted = status.isGranted;
    context.read<SetupNotifier>().setCameraGranted(granted);
    setState(() => _loading = false);

    if (granted) {
      await context.read<VoiceService>().speak('Shukriya! Camera mil gaya.');
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pushReplacementNamed(context, '/setup/location');
    } else {
      setState(() => _denied = true);
      await context.read<VoiceService>().speak(
            'Koi baat nahi. Settings mein baad mein de sakte hain.',
          );
    }
  }

  Future<void> _skip() async {
    await context.read<VoiceService>().speak('Theek hai, baad mein denge.');
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/setup/location');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      step: SetupStep.camera,
      title: 'Camera Permission',
      subtitle: 'Drishti ko raasta dikhaane ke liye camera chahiye.',
      icon: _CameraIcon(denied: _denied),
      body: Column(
        children: [
          if (_denied)
            const _DeniedBanner(
              message: 'Koi baat nahi. Settings mein baad mein de sakte hain.',
            )
                .animate()
                .fadeIn(duration: 300.ms)
                .shake(hz: 3, offset: const Offset(4, 0)),
          if (_denied) const SizedBox(height: AppSizes.lg),
          SetupPermissionButtons(
            onAllow: _requestCamera,
            onSkip: _skip,
            loading: _loading,
          ),
        ],
      ),
    );
  }
}

class _CameraIcon extends StatelessWidget {
  final bool denied;
  const _CameraIcon({this.denied = false});

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
                  AppColors.saffronLight.withValues(alpha: 0.25),
                  AppColors.saffron.withValues(alpha: 0.08),
                ],
        ),
        border: Border.all(
          color: denied
              ? AppColors.hazardRed.withValues(alpha: 0.5)
              : AppColors.saffron.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Icon(
        denied ? Icons.no_photography_rounded : Icons.camera_alt_rounded,
        size: 56,
        color: denied ? AppColors.hazardRed : AppColors.saffron,
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
          end: denied ? 1.0 : 1.08,
          duration: 2000.ms,
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
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.hazardRed),
            ),
          ),
        ],
      ),
    );
  }
}
