import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Slide 3 Illustration: Guardian watching a map, user safe on street.
/// Warm, reassuring composition — guardian on laptop above, user below.
class GuardianMapIllustration extends StatefulWidget {
  const GuardianMapIllustration({super.key});

  @override
  State<GuardianMapIllustration> createState() => _GuardianMapIllustrationState();
}

class _GuardianMapIllustrationState extends State<GuardianMapIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF050A1E), Color(0xFF0A1030), Color(0xFF1A2050)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          painter: _GuardianPainter(pulse: _ctrl.value),
        ),
      ),
    );
  }
}

class _GuardianPainter extends CustomPainter {
  final double pulse;
  const _GuardianPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // ── Connection line (guardian → user) ───────────────────────────
    final connPaint = Paint()
      ..color = AppColors.saffron.withOpacity(0.15 + 0.1 * pulse)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(W * 0.35, H * 0.3), Offset(W * 0.5, H * 0.73), connPaint);

    // ── Guardian (top-left quadrant) ─────────────────────────────────
    _drawGuardian(canvas, Offset(W * 0.28, H * 0.25), H * 0.18);

    // ── Laptop with map ──────────────────────────────────────────────
    _drawLaptop(canvas, Offset(W * 0.28, H * 0.28), size);

    // ── Safe zone circle on map ──────────────────────────────────────
    final safeGlow = Paint()
      ..color = AppColors.safeGreen.withOpacity(0.18 + 0.12 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(Offset(W * 0.62, H * 0.24), 18 + 6 * pulse, safeGlow);

    final safeRing = Paint()
      ..color = AppColors.safeGreen.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(W * 0.62, H * 0.24), 14, safeRing);

    // ── User location dot on map ─────────────────────────────────────
    canvas.drawCircle(
      Offset(W * 0.62, H * 0.24),
      5,
      Paint()..color = AppColors.saffron,
    );

    // ── Street below ─────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTRB(0, H * 0.62, W, H),
      Paint()..color = const Color(0xFF11112A),
    );

    // ── Walking user (bottom centre) ─────────────────────────────────
    _drawUser(canvas, Offset(W * 0.5, H * 0.73), H * 0.16);

    // ── Safe aura around user ─────────────────────────────────────────
    final userAura = Paint()
      ..color = AppColors.safeGreen.withOpacity(0.12 + 0.08 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(Offset(W * 0.5, H * 0.74), H * 0.12, userAura);

    // ── Signal arcs from guardian to user ───────────────────────────
    for (var i = 1; i <= 3; i++) {
      final r = 20.0 * i + 10 * pulse;
      final arcPaint = Paint()
        ..color = AppColors.saffron.withOpacity((0.5 - i * 0.12) * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(W * 0.28, H * 0.25), width: r * 2, height: r * 2),
        0.5,
        2.0,
        false,
        arcPaint,
      );
    }

    // ── Stars ────────────────────────────────────────────────────────
    final starPaint = Paint()..color = Colors.white.withOpacity(0.5);
    final stars = [
      Offset(W * 0.1, H * 0.05), Offset(W * 0.55, H * 0.02),
      Offset(W * 0.78, H * 0.08), Offset(W * 0.9, H * 0.05),
    ];
    for (final s in stars) {
      canvas.drawCircle(s, 1.5, starPaint);
    }
  }

  void _drawGuardian(Canvas canvas, Offset center, double size) {
    final skinPaint = Paint()..color = const Color(0xFFD4956A);
    final clothPaint = Paint()..color = const Color(0xFF2D4A7A);

    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, size * 0.25), width: size * 0.6, height: size * 0.5),
        const Radius.circular(6),
      ),
      clothPaint,
    );
    // Head
    canvas.drawCircle(center.translate(0, -size * 0.1), size * 0.22, skinPaint);
  }

  void _drawLaptop(Canvas canvas, Offset center, Size size) {
    final W = size.width;
    final H = size.height;
    final laptopPaint = Paint()..color = const Color(0xFF1E2A3E);
    final screenPaint = Paint()..color = const Color(0xFF0A2040);

    // Screen
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(W * 0.06, H * 0.1, W * 0.52, H * 0.38),
        const Radius.circular(6),
      ),
      laptopPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(W * 0.09, H * 0.12, W * 0.49, H * 0.36),
        const Radius.circular(4),
      ),
      screenPaint,
    );

    // Map grid
    _drawMapGrid(canvas, Rect.fromLTRB(W * 0.09, H * 0.12, W * 0.49, H * 0.36), size);

    // Base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(W * 0.04, H * 0.38, W * 0.54, H * 0.40),
        const Radius.circular(2),
      ),
      laptopPaint,
    );
  }

  void _drawMapGrid(Canvas canvas, Rect bounds, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.saffron.withOpacity(0.15)
      ..strokeWidth = 0.5;

    for (var i = 1; i < 4; i++) {
      final x = bounds.left + bounds.width * i / 4;
      canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), gridPaint);
    }
    for (var i = 1; i < 3; i++) {
      final y = bounds.top + bounds.height * i / 3;
      canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), gridPaint);
    }

    // Route line on map
    final routePaint = Paint()
      ..color = AppColors.saffron.withOpacity(0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(bounds.left + 20, bounds.bottom - 10),
      Offset(bounds.left + bounds.width * 0.6, bounds.top + 15),
      routePaint,
    );
  }

  void _drawUser(Canvas canvas, Offset center, double height) {
    final skinPaint = Paint()..color = const Color(0xFFE8C49A);
    final clothPaint = Paint()..color = const Color(0xFF1A3A6A);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, height * 0.1), width: height * 0.28, height: height * 0.38),
        const Radius.circular(6),
      ),
      clothPaint,
    );
    canvas.drawCircle(center.translate(0, -height * 0.28), height * 0.14, skinPaint);

    // Cane
    final canePaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      center.translate(height * 0.1, 0),
      center.translate(height * 0.24, height * 0.48),
      canePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GuardianPainter old) => old.pulse != pulse;
}
