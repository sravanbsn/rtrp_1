import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Slide 2 Illustration: Phone camera scanning street, hazard glowing red.
class CameraScanIllustration extends StatefulWidget {
  const CameraScanIllustration({super.key});

  @override
  State<CameraScanIllustration> createState() => _CameraScanIllustrationState();
}

class _CameraScanIllustrationState extends State<CameraScanIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scanLine;
  late Animation<double> _hazardPulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _scanLine = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.8, curve: Curves.easeInOut)),
    );
    _hazardPulse = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1, curve: Curves.easeInOut)),
    );
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
          colors: [Color(0xFF080422), Color(0xFF0D0D33), Color(0xFF1A0A1A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _CameraScanPainter(
              scanProgress: _scanLine.value,
              hazardPulse: _hazardPulse.value,
            ),
          );
        },
      ),
    );
  }
}

class _CameraScanPainter extends CustomPainter {
  final double scanProgress;
  final double hazardPulse;

  const _CameraScanPainter({required this.scanProgress, required this.hazardPulse});

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // ── Street / ground ─────────────────────────────────────────────
    final groundPaint = Paint()..color = const Color(0xFF1A1830);
    canvas.drawRect(Rect.fromLTRB(0, H * 0.62, W, H), groundPaint);

    // ── Camera viewfinder frame ──────────────────────────────────────
    final framePaint = Paint()
      ..color = AppColors.saffron.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final frameRect = Rect.fromCenter(
      center: Offset(W / 2, H * 0.42),
      width: W * 0.72,
      height: H * 0.58,
    );

    // Corner brackets (camera UI feel)
    _drawCornerBracket(canvas, frameRect.topLeft, 20, framePaint);
    _drawCornerBracket(canvas, frameRect.topRight, 20, framePaint, flipX: true);
    _drawCornerBracket(canvas, frameRect.bottomLeft, 20, framePaint, flipY: true);
    _drawCornerBracket(canvas, frameRect.bottomRight, 20, framePaint, flipX: true, flipY: true);

    // ── Scan line ────────────────────────────────────────────────────
    final scanY = frameRect.top + (frameRect.height * scanProgress);
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          AppColors.saffron.withOpacity(0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(frameRect.left, scanY - 2, frameRect.width, 4))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(frameRect.left, scanY),
      Offset(frameRect.right, scanY),
      scanPaint,
    );

    // ── Hazard obstacle (pothole/step) ───────────────────────────────
    final hazardCenter = Offset(W * 0.5, H * 0.64);
    final hazardGlow = Paint()
      ..color = AppColors.hazardRed.withOpacity(0.3 * hazardPulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(hazardCenter, 36 * hazardPulse, hazardGlow);

    final hazardPaint = Paint()..color = AppColors.hazardRed.withOpacity(0.85 * hazardPulse);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: hazardCenter, width: 60, height: 18),
        const Radius.circular(4),
      ),
      hazardPaint,
    );

    // Warning icon
    final iconPaint = Paint()..color = Colors.white.withOpacity(hazardPulse);
    _drawWarningTriangle(canvas, hazardCenter.translate(0, -40), 16, iconPaint);

    // ── Grid overlay on ground ───────────────────────────────────────
    final gridPaint = Paint()
      ..color = AppColors.saffron.withOpacity(0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 0; i < 8; i++) {
      canvas.drawLine(
        Offset(W * i / 7, H * 0.62),
        Offset(W / 2, H * 0.42),
        gridPaint,
      );
    }

    // ── Phone outline ────────────────────────────────────────────────
    _drawPhoneFrame(canvas, size);
  }

  void _drawCornerBracket(Canvas canvas, Offset corner, double size, Paint paint,
      {bool flipX = false, bool flipY = false}) {
    final dx = flipX ? -size : size;
    final dy = flipY ? -size : size;

    canvas.drawPath(
      Path()
        ..moveTo(corner.dx + dx, corner.dy)
        ..lineTo(corner.dx, corner.dy)
        ..lineTo(corner.dx, corner.dy + dy),
      paint,
    );
  }

  void _drawWarningTriangle(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy - size);
    path.lineTo(center.dx + size * math.cos(math.pi / 6),
        center.dy + size * math.sin(math.pi / 6));
    path.lineTo(center.dx - size * math.cos(math.pi / 6),
        center.dy + size * math.sin(math.pi / 6));
    path.close();
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    canvas.drawPath(path, paint);
    // Exclamation
    canvas.drawLine(center, center.translate(0, size * 0.4), paint..strokeWidth = 2);
    canvas.drawCircle(center.translate(0, size * 0.6), 2, paint..style = PaintingStyle.fill);
  }

  void _drawPhoneFrame(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;
    final phonePaint = Paint()
      ..color = const Color(0xFF2A2A3E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(W / 2, H * 0.42), width: W * 0.78, height: H * 0.68),
        const Radius.circular(24),
      ),
      phonePaint,
    );
    // Camera lens dot
    canvas.drawCircle(
      Offset(W / 2, H * 0.082),
      8,
      Paint()..color = const Color(0xFF3A3A5E),
    );
  }

  @override
  bool shouldRepaint(covariant _CameraScanPainter old) =>
      old.scanProgress != scanProgress || old.hazardPulse != hazardPulse;
}
