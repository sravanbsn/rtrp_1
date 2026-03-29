import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Pulsing glowing orb — Drishti's visual identity on the splash screen.
/// Uses nested animated containers with varying opacity for a soft bloom effect.
class OrbAnimation extends StatefulWidget {
  const OrbAnimation({super.key});

  @override
  State<OrbAnimation> createState() => _OrbAnimationState();
}

class _OrbAnimationState extends State<OrbAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow halo
              Transform.scale(
                scale: _pulse.value * 1.25,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.orbOuter,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Mid ring
              Transform.scale(
                scale: _pulse.value * 1.05,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.orbMid,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Core orb
              Transform.scale(
                scale: _pulse.value,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        AppColors.orbCore,
                        AppColors.saffron,
                        AppColors.saffronDark,
                      ],
                      stops: [0.0, 0.6, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.saffron.withOpacity(0.6),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const _EyeIcon(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Stylised eye — Drishti's symbol.
class _EyeIcon extends StatelessWidget {
  const _EyeIcon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: CustomPaint(
        painter: _EyePainter(),
      ),
    );
  }
}

class _EyePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.navyDeep
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Outer eye shape (almond)
    final eyePath = Path();
    eyePath.moveTo(0, cy);
    eyePath.quadraticBezierTo(cx, cy - size.height * 0.45, size.width, cy);
    eyePath.quadraticBezierTo(cx, cy + size.height * 0.45, 0, cy);
    canvas.drawPath(
        eyePath, paint..color = AppColors.navyDeep.withOpacity(0.3));

    // Iris
    canvas.drawCircle(
        Offset(cx, cy), size.width * 0.28, paint..color = AppColors.navyDeep);

    // Pupil highlight
    canvas.drawCircle(
      Offset(cx + size.width * 0.08, cy - size.height * 0.08),
      size.width * 0.07,
      paint..color = Colors.white.withOpacity(0.8),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
