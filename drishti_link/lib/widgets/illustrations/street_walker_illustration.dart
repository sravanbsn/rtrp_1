import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Slide 1 Illustration: Confident person walking on a warm, busy Indian street.
/// Pure code-painted — warm amber tones, saffron sky gradient.
class StreetWalkerIllustration extends StatelessWidget {
  const StreetWalkerIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1A1040), // top — deep purple-navy
            Color(0xFF2D1B69), // mid
            Color(0xFF4A2C4A), // bottom warm
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: CustomPaint(
        painter: _StreetScenePainter(),
        child: Container(),
      ),
    );
  }
}

class _StreetScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // ── Sky gradient ────────────────────────────────────────────────
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0F0730), Color(0xFF3D1A5E), Color(0xFF7B3F00)],
        stops: [0, 0.5, 1],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, W, H * 0.6));
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H * 0.6), skyPaint);

    // ── Street ──────────────────────────────────────────────────────
    final streetPaint = Paint()..color = const Color(0xFF1E1E2E);
    final streetPath = Path()
      ..moveTo(0, H * 0.65)
      ..lineTo(W, H * 0.55)
      ..lineTo(W, H)
      ..lineTo(0, H)
      ..close();
    canvas.drawPath(streetPath, streetPaint);

    // ── Street lights ───────────────────────────────────────────────
    _drawStreetLight(canvas, Offset(W * 0.15, H * 0.35), H * 0.3);
    _drawStreetLight(canvas, Offset(W * 0.82, H * 0.3), H * 0.28);

    // ── Buildings silhouette ────────────────────────────────────────
    _drawBuildings(canvas, size);

    // ── Saffron path glow ───────────────────────────────────────────
    final pathGlow = Paint()
      ..color = AppColors.saffron.withOpacity(0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawPath(streetPath, pathGlow);

    // ── Walking person silhouette ───────────────────────────────────
    _drawPerson(canvas, Offset(W * 0.48, H * 0.58), H * 0.22);

    // ── Drishti glow aura around person ──────────────────────────────
    final auraPaint = Paint()
      ..color = AppColors.saffron.withOpacity(0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(Offset(W * 0.48, H * 0.5), H * 0.18, auraPaint);

    // ── Stars ───────────────────────────────────────────────────────
    _drawStars(canvas, size);
  }

  void _drawStreetLight(Canvas canvas, Offset base, double height) {
    final pole = Paint()..color = const Color(0xFF5A5A6E);
    canvas.drawRect(
      Rect.fromCenter(center: base, width: 4, height: height),
      pole,
    );
    final glowPaint = Paint()
      ..color = AppColors.saffronLight.withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(base.translate(0, -height / 2), 12, glowPaint);
    final lamp = Paint()..color = AppColors.saffronLight;
    canvas.drawCircle(base.translate(0, -height / 2), 5, lamp);
  }

  void _drawBuildings(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;
    final buildingPaint = Paint()..color = const Color(0xFF12102A);

    final buildings = [
      Rect.fromLTRB(0, H * 0.12, W * 0.18, H * 0.55),
      Rect.fromLTRB(W * 0.14, H * 0.2, W * 0.32, H * 0.55),
      Rect.fromLTRB(W * 0.60, H * 0.15, W * 0.78, H * 0.52),
      Rect.fromLTRB(W * 0.75, H * 0.22, W, H * 0.55),
    ];
    for (final r in buildings) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        buildingPaint,
      );
    }

    // Window lights
    final windowPaint = Paint()..color = AppColors.saffronLight.withOpacity(0.5);
    final windows = [
      Offset(W * 0.06, H * 0.22), Offset(W * 0.12, H * 0.30),
      Offset(W * 0.21, H * 0.28), Offset(W * 0.25, H * 0.38),
      Offset(W * 0.65, H * 0.25), Offset(W * 0.72, H * 0.32),
      Offset(W * 0.80, H * 0.30), Offset(W * 0.88, H * 0.38),
    ];
    for (final w in windows) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: w, width: 6, height: 8),
          const Radius.circular(1),
        ),
        windowPaint,
      );
    }
  }

  void _drawPerson(Canvas canvas, Offset center, double height) {
    final paint = Paint()..color = const Color(0xFFE8C49A); // warm skin tone
    final darkPaint = Paint()..color = const Color(0xFF2A1F3D); // clothes

    // Body (torso)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, height * 0.1), width: height * 0.28, height: height * 0.38),
        const Radius.circular(8),
      ),
      darkPaint,
    );

    // Head
    canvas.drawCircle(center.translate(0, -height * 0.28), height * 0.13, paint);

    // Legs (walking pose)
    final legPaint = Paint()
      ..color = const Color(0xFF1A1230)
      ..strokeWidth = height * 0.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center.translate(-height * 0.04, height * 0.28),
        center.translate(-height * 0.12, height * 0.5), legPaint);
    canvas.drawLine(center.translate(height * 0.04, height * 0.28),
        center.translate(height * 0.06, height * 0.5), legPaint);

    // Cane (white)
    final canePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      center.translate(height * 0.1, height * 0.0),
      center.translate(height * 0.25, height * 0.5),
      canePaint,
    );
  }

  void _drawStars(Canvas canvas, Size size) {
    final starPaint = Paint()..color = Colors.white.withOpacity(0.7);
    final positions = [
      Offset(size.width * 0.05, size.height * 0.05),
      Offset(size.width * 0.25, size.height * 0.08),
      Offset(size.width * 0.45, size.height * 0.04),
      Offset(size.width * 0.65, size.height * 0.07),
      Offset(size.width * 0.85, size.height * 0.03),
      Offset(size.width * 0.92, size.height * 0.12),
      Offset(size.width * 0.35, size.height * 0.12),
    ];
    for (final p in positions) {
      canvas.drawCircle(p, 1.5, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
