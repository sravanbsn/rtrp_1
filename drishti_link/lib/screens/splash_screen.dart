import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';
import '../widgets/drishti_voice_bar.dart';
import '../widgets/waveform_animation.dart';
import '../widgets/orb_animation.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const String _drishtiGreeting =
      'Namaste. Main Drishti hoon. Main aapki aankhein hoon.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSplash());
  }

  Future<void> _startSplash() async {
    // Brief delay so widgets have rendered before TTS fires
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final voice = context.read<VoiceService>();
    await voice.speak(_drishtiGreeting);

    // Wait for at least 3 seconds total splash time
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    Navigator.pushReplacementNamed(context, '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            Column(
              children: [
                const Spacer(flex: 2),

                // ── Glowing orb ──────────────────────────────────────
                const OrbAnimation()
                    .animate()
                    .fadeIn(duration: 800.ms, curve: Curves.easeOut),

                const SizedBox(height: 40),

                // ── App name ─────────────────────────────────────────
                _AppTitle()
                    .animate(delay: 400.ms)
                    .fadeIn(duration: 800.ms)
                    .slideY(begin: 0.2, end: 0, duration: 800.ms, curve: Curves.easeOut),

                const SizedBox(height: 8),

                Text(
                  'अपनी आँखें',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.saffronLight,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 1.5,
                  ),
                )
                    .animate(delay: 700.ms)
                    .fadeIn(duration: 600.ms),

                const Spacer(flex: 3),

                // ── Waveform ──────────────────────────────────────────
                const WaveformAnimation()
                    .animate(delay: 300.ms)
                    .fadeIn(duration: 600.ms),

                const SizedBox(height: 16),
              ],
            ),

            // ── Persistent voice bar ──────────────────────────────────
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

class _AppTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (Rect bounds) {
            return const LinearGradient(
              colors: [AppColors.white, AppColors.saffronLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds);
          },
          child: Text(
            'Drishti-Link',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: Colors.white, // Masked by shader
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
