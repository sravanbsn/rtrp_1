import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';

/// Hero mic orb — the primary visual CTA for every voice-input step.
/// Three states: [listening] pulsing saffron | [confirming] static | [loading] spinning ring
class ListeningMicOrb extends StatefulWidget {
  final ListeningOrbState state;
  final VoidCallback? onTap;

  const ListeningMicOrb({
    super.key,
    this.state = ListeningOrbState.listening,
    this.onTap,
  });

  @override
  State<ListeningMicOrb> createState() => _ListeningMicOrbState();
}

enum ListeningOrbState { listening, confirming, loading, done }

class _ListeningMicOrbState extends State<ListeningMicOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.25, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(ListeningMicOrb old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.state == ListeningOrbState.listening) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Outer pulse ring (listening only) ──────────────────
            if (widget.state == ListeningOrbState.listening)
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Transform.scale(
                  scale: _pulseScale.value,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.saffron.withOpacity(_pulseOpacity.value),
                    ),
                  ),
                ),
              ),

            // ── Mid ring ───────────────────────────────────────────
            if (widget.state == ListeningOrbState.listening)
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Transform.scale(
                  scale: (_pulseScale.value - 1.0) * 0.6 + 1.0,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.saffron
                          .withOpacity(_pulseOpacity.value * 0.5),
                    ),
                  ),
                ),
              ),

            // ── Loading spinner ring ────────────────────────────────
            if (widget.state == ListeningOrbState.loading)
              const SizedBox(
                width: 148,
                height: 148,
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.saffron),
                  strokeWidth: 3,
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .rotate(duration: 1200.ms),

            // ── Core orb ───────────────────────────────────────────
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: _orbColors(widget.state),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _glowColor(widget.state),
                    blurRadius: 32,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                _orbIcon(widget.state),
                color: AppColors.navyDeep,
                size: 48,
                semanticLabel: _orbLabel(widget.state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _orbColors(ListeningOrbState s) {
    switch (s) {
      case ListeningOrbState.listening:
        return [AppColors.saffronLight, AppColors.saffron, AppColors.saffronDark];
      case ListeningOrbState.confirming:
        return [const Color(0xFFFFE0A0), AppColors.saffron, AppColors.saffronDark];
      case ListeningOrbState.loading:
        return [AppColors.navyLight, AppColors.navyCard, AppColors.navyMid];
      case ListeningOrbState.done:
        return [const Color(0xFF66FFB0), AppColors.safeGreen, const Color(0xFF22BB66)];
    }
  }

  Color _glowColor(ListeningOrbState s) {
    switch (s) {
      case ListeningOrbState.listening:
      case ListeningOrbState.confirming:
        return AppColors.saffron.withOpacity(0.45);
      case ListeningOrbState.loading:
        return AppColors.navyLight.withOpacity(0.4);
      case ListeningOrbState.done:
        return AppColors.safeGreen.withOpacity(0.45);
    }
  }

  IconData _orbIcon(ListeningOrbState s) {
    switch (s) {
      case ListeningOrbState.listening:
        return Icons.mic_rounded;
      case ListeningOrbState.confirming:
        return Icons.hearing_rounded;
      case ListeningOrbState.loading:
        return Icons.hourglass_top_rounded;
      case ListeningOrbState.done:
        return Icons.check_rounded;
    }
  }

  String _orbLabel(ListeningOrbState s) {
    switch (s) {
      case ListeningOrbState.listening:
        return 'Drishti is listening. Tap to activate microphone.';
      case ListeningOrbState.confirming:
        return 'Drishti heard you. Waiting for confirmation.';
      case ListeningOrbState.loading:
        return 'Processing...';
      case ListeningOrbState.done:
        return 'Done!';
    }
  }
}
