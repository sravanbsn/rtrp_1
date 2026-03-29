import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/theme.dart';
import '../services/voice_service.dart';

// ── Mock data (replace with real data layer) ───────────────────────────────
const _userName = 'Arjun';
const _guardianName = 'Priya';

const _stats = {
  'walks': 3,
  'alerts': 1,
  'hazards': 5,
};

const _lastRoute = {
  'from': 'Ghar',
  'to': 'Market',
  'duration': '8 min',
  'hazards': '2 hazards avoided',
};

// ── Voice commands ──────────────────────────────────────────────────────────
const _helpText = 'Commands: "Chalna shuru karo" — navigation start. '
    '"Meri alerts batao" — last 3 alerts. '
    '"Priya ko call karo" — guardian call. '
    '"Mera route batao" — last safe route. '
    '"Help" — yeh list.';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ── Navigation tab ──────────────────────────────────────────────
  int _tabIndex = 0;

  // ── CTA pulse animation ─────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // ── STT ─────────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  // ── Greeting spoken flag ─────────────────────────────────────────
  // (greeting happens once in _initVoice)

  @override
  void initState() {
    super.initState();

    // Pulse ring around the CTA button
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _initVoice();
  }

  Future<void> _initVoice() async {
    _speechAvailable = await _speech.initialize();
    if (!mounted) return;

    // Greeting
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await context.read<VoiceService>().speak(
          '$_userName, sab theek hai. '
          '$_guardianName aapko dekh rahi hain. Chalna shuru karein?',
        );
    if (!mounted) return;

    // Start persistent listen loop
    _listenLoop();
  }

  // Always-on listen loop — restarts after each result / timeout
  void _listenLoop() {
    if (!_speechAvailable || !mounted) return;
    setState(() => _isListening = true);

    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 5),
      onResult: (result) {
        if (!result.finalResult) return;
        _handleCommand(result.recognizedWords.toLowerCase());
        // Restart after a brief delay
        Future.delayed(const Duration(milliseconds: 1500), _listenLoop);
      },
    );
  }

  Future<void> _handleCommand(String words) async {
    final voice = context.read<VoiceService>();

    if (words.contains('chalna') ||
        words.contains('start') ||
        words.contains('navigation')) {
      await voice.speak('Navigation shuru kar rahi hoon. Seedha chalo.');
      // TODO: navigate to NavigationScreen
    } else if (words.contains('alert')) {
      Navigator.pushNamed(context, '/alerts');
    } else if (words.contains('call') || words.contains('priya')) {
      await voice.speak('$_guardianName ko call kar rahi hoon.');
      // TODO: launch_url / phone dialer
    } else if (words.contains('route') || words.contains('rasta')) {
      await voice.speak(
        'Aapka last route: ${_lastRoute["from"]} se ${_lastRoute["to"]}. '
        '${_lastRoute["duration"]}. ${_lastRoute["hazards"]}.',
      );
    } else if (words.contains('help') || words.contains('madad')) {
      await voice.speak(_helpText);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Saffron ambient glow ──────────────────────────────
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.1),
                      radius: 0.85,
                      colors: [
                        AppColors.saffron.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Column(
              children: [
                // ══ TOP BAR ══════════════════════════════════════
                const _TopBar(
                  userName: _userName,
                  guardianName: _guardianName,
                ),

                // ══ SCROLLABLE BODY ═══════════════════════════════
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                    child: Column(
                      children: [
                        SizedBox(height: size.height * 0.03),

                        // ══ GIANT CTA BUTTON ══════════════════════
                        _StartButton(
                          pulseAnim: _pulseAnim,
                          size: size,
                          onTap: () {
                            HapticFeedback.heavyImpact();
                            context.read<VoiceService>().speak(
                                  'Navigation shuru kar rahi hoon.',
                                );
                            Navigator.pushNamed(context, '/navigation');
                          },
                        ),

                        SizedBox(height: size.height * 0.04),

                        // ══ STATS ROW ═════════════════════════════
                        _StatsRow(),

                        const SizedBox(height: AppSizes.lg),

                        // ══ LAST ROUTE CARD ═══════════════════════
                        _LastRouteCard(
                          onRepeat: () {
                            HapticFeedback.mediumImpact();
                            context.read<VoiceService>().speak(
                                  '${_lastRoute["from"]} se ${_lastRoute["to"]} route shuru kar rahi hoon.',
                                );
                          },
                        ),

                        // Voice bar clearance
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ══ PERSISTENT VOICE BAR (always on top) ═════════════
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _PersistentVoiceBar(isListening: _isListening),
            ),
          ],
        ),
      ),

      // ══ BOTTOM NAVIGATION ═════════════════════════════════════
      bottomNavigationBar: _BottomNav(
        currentIndex: _tabIndex,
        onTap: (i) {
          if (i == 1) {
            Navigator.pushNamed(context, '/routes');
            return;
          }
          if (i == 2) {
            Navigator.pushNamed(context, '/alerts');
            return;
          }
          if (i == 3) {
            Navigator.pushNamed(context, '/profile');
            return;
          }
          setState(() => _tabIndex = i);
          HapticFeedback.selectionClick();
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String userName;
  final String guardianName;

  const _TopBar({required this.userName, required this.guardianName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Greeting + Guardian pill ────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Namaste, $userName 👋',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ).animate().fadeIn(duration: 500.ms),

                const SizedBox(height: AppSizes.sm),

                // Guardian status pill
                Semantics(
                  label: '$guardianName is watching you — safe',
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.safeGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(
                          color: AppColors.safeGreen.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.safeGreen,
                            shape: BoxShape.circle,
                          ),
                        )
                            .animate(onPlay: (c) => c.repeat())
                            .scaleXY(
                              end: 1.4,
                              duration: 900.ms,
                              curve: Curves.easeOut,
                            )
                            .then()
                            .scaleXY(end: 1.0, duration: 600.ms),
                        const SizedBox(width: 6),
                        Text(
                          '🟢 $guardianName dekh rahi hai',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.safeGreen,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ).animate(delay: 200.ms).fadeIn(duration: 400.ms),
              ],
            ),
          ),

          // ── Status icons ─────────────────────────────────────
          const _StatusIcons(),
        ],
      ),
    );
  }
}

class _StatusIcons extends StatelessWidget {
  const _StatusIcons();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: const Row(
        children: [
          // Battery
          Icon(Icons.battery_5_bar_rounded,
              color: AppColors.safeGreen, size: 22),
          SizedBox(width: 4),
          // WiFi / signal
          Icon(Icons.signal_cellular_alt_rounded,
              color: AppColors.textSecondary, size: 20),
        ],
      ).animate(delay: 300.ms).fadeIn(duration: 400.ms),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// GIANT CTA START BUTTON
// ────────────────────────────────────────────────────────────────────────────

class _StartButton extends StatelessWidget {
  final Animation<double> pulseAnim;
  final Size size;
  final VoidCallback onTap;

  const _StartButton({
    required this.pulseAnim,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final btnSize = size.width * 0.62;

    return Column(
      children: [
        Semantics(
          label: 'Start navigation. Double tap to activate.',
          button: true,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: btnSize + 40,
              height: btnSize + 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ── Outermost pulse ring ─────────────────────
                  AnimatedBuilder(
                    animation: pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: pulseAnim.value,
                      child: Container(
                        width: btnSize + 36,
                        height: btnSize + 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.saffron
                              .withValues(alpha: 0.06 * (2 - pulseAnim.value)),
                        ),
                      ),
                    ),
                  ),

                  // ── Middle ring ──────────────────────────────
                  AnimatedBuilder(
                    animation: pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: 0.95 + (pulseAnim.value - 1.0) * 0.6,
                      child: Container(
                        width: btnSize + 16,
                        height: btnSize + 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.saffron.withValues(alpha: 0.25),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Main button ──────────────────────────────
                  Container(
                    width: btnSize,
                    height: btnSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [
                          AppColors.saffronLight,
                          AppColors.saffron,
                          AppColors.saffronDark,
                        ],
                        stops: [0.0, 0.6, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.saffron.withValues(alpha: 0.45),
                          blurRadius: 48,
                          spreadRadius: 8,
                        ),
                        BoxShadow(
                          color: AppColors.saffron.withValues(alpha: 0.2),
                          blurRadius: 80,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.directions_walk_rounded,
                          color: AppColors.navyDeep,
                          size: 64,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'CHALNA\nSHURU KARO',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.navyDeep,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                            letterSpacing: 1.5,
                            fontFamily: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.fontFamily,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 600.ms).scaleXY(
                      begin: 0.85,
                      end: 1.0,
                      curve: Curves.elasticOut,
                      duration: 800.ms),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSizes.md),

        // Sub-caption
        Text(
          'Tap anywhere ya bolein "Chalna shuru karo"',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
          textAlign: TextAlign.center,
        ).animate(delay: 700.ms).fadeIn(duration: 500.ms),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// STATS ROW
// ────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        label: 'Aaj ke\nWalks',
        value: '${_stats["walks"]}',
        icon: Icons.directions_walk_rounded,
        color: AppColors.saffron
      ),
      (
        label: 'Alerts\nAaj',
        value: '${_stats["alerts"]}',
        icon: Icons.notifications_rounded,
        color: const Color(0xFFFF6B6B)
      ),
      (
        label: 'Hazards\nAvoided',
        value: '${_stats["hazards"]}',
        icon: Icons.shield_rounded,
        color: AppColors.safeGreen
      ),
    ];

    return Row(
      children: cards.asMap().entries.map((entry) {
        final i = entry.key;
        final card = entry.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: i == 0 ? 0 : AppSizes.sm / 2,
              right: i == 2 ? 0 : AppSizes.sm / 2,
            ),
            child: Semantics(
              label: '${card.label.replaceAll('\n', ' ')}: ${card.value}',
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSizes.md, horizontal: AppSizes.sm),
                decoration: BoxDecoration(
                  color: AppColors.navyCard,
                  borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                  border: Border.all(color: card.color.withValues(alpha: 0.25)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(card.icon, color: card.color, size: 26),
                    const SizedBox(height: 6),
                    Text(
                      card.value,
                      style: TextStyle(
                        color: card.color,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            height: 1.3,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
              .animate(delay: Duration(milliseconds: 400 + i * 100))
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.15, end: 0),
        );
      }).toList(),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// LAST ROUTE CARD
// ────────────────────────────────────────────────────────────────────────────

class _LastRouteCard extends StatelessWidget {
  final VoidCallback onRepeat;
  const _LastRouteCard({required this.onRepeat});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Last route: ${_lastRoute["from"]} to ${_lastRoute["to"]}. ${_lastRoute["duration"]}. ${_lastRoute["hazards"]}.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSizes.lg),
        decoration: BoxDecoration(
          color: AppColors.navyCard,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(color: AppColors.navyLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                const Icon(Icons.route_rounded,
                    color: AppColors.saffron, size: 20),
                const SizedBox(width: AppSizes.sm),
                Text(
                  'Pichla Route',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                ),
              ],
            ),

            const SizedBox(height: AppSizes.sm),

            // Route line
            Text(
              '${_lastRoute["from"]} → ${_lastRoute["to"]}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 22,
                  ),
            ),

            const SizedBox(height: AppSizes.xs),

            // Chips row
            Row(
              children: [
                _RouteChip(
                    text: '⏱ ${_lastRoute["duration"]}',
                    color: AppColors.saffron),
                const SizedBox(width: AppSizes.sm),
                _RouteChip(
                    text: '🛡 ${_lastRoute["hazards"]}',
                    color: AppColors.safeGreen),
              ],
            ),

            const SizedBox(height: AppSizes.lg),

            // Repeat button
            Semantics(
              label: 'Repeat last route from home to market',
              button: true,
              child: ElevatedButton.icon(
                onPressed: onRepeat,
                icon: const Icon(Icons.replay_rounded,
                    color: AppColors.navyDeep, size: 20),
                label: const Text('Wahi Route Dobara'),
                style: ElevatedButton.styleFrom(
                  minimumSize:
                      const Size(double.infinity, AppSizes.minTouchTarget),
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: 700.ms)
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.08, end: 0);
  }
}

class _RouteChip extends StatelessWidget {
  final String text;
  final Color color;
  const _RouteChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// PERSISTENT VOICE BAR
// ────────────────────────────────────────────────────────────────────────────

class _PersistentVoiceBar extends StatelessWidget {
  final bool isListening;
  const _PersistentVoiceBar({required this.isListening});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isListening
          ? 'Drishti is listening. Say a voice command.'
          : 'Drishti voice bar',
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.md),
        decoration: const BoxDecoration(
          color: AppColors.navyMid,
          border: Border(
            top: BorderSide(color: AppColors.navyLight, width: 1),
          ),
        ),
        child: Row(
          children: [
            // Pulsing mic
            AnimatedContainer(
              duration: AppDurations.medium,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isListening
                    ? AppColors.saffron.withValues(alpha: 0.2)
                    : AppColors.navyCard,
                border: Border.all(
                  color: isListening ? AppColors.saffron : AppColors.navyLight,
                ),
              ),
              child: Icon(
                isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: isListening ? AppColors.saffron : AppColors.textMuted,
                size: 18,
              ),
            )
                .animate(
                    onPlay: (c) => isListening ? c.repeat(reverse: true) : null)
                .scaleXY(
                  end: isListening ? 1.12 : 1.0,
                  duration: 900.ms,
                  curve: Curves.easeInOut,
                ),

            const SizedBox(width: AppSizes.md),

            Expanded(
              child: Text(
                isListening
                    ? '🎙 Drishti sun rahi hai...'
                    : '🎙 Drishti kaafi der baad sunegi...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isListening
                          ? AppColors.saffronLight
                          : AppColors.textMuted,
                      fontWeight:
                          isListening ? FontWeight.w600 : FontWeight.w400,
                    ),
              ),
            ),

            // Help hint
            Semantics(
              label: 'Show all voice commands',
              button: true,
              child: GestureDetector(
                onTap: () {
                  context.read<VoiceService>().speak(_helpText);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.navyCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.navyLight),
                  ),
                  child: Text(
                    'Help',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// BOTTOM NAV
// ────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = [
      (icon: Icons.home_rounded, label: 'Ghar'),
      (icon: Icons.map_rounded, label: 'Routes'),
      (icon: Icons.notifications_rounded, label: 'Alerts'),
      (icon: Icons.person_rounded, label: 'Profile'),
    ];

    return Container(
      // Extra padding above the voice bar
      padding: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        color: AppColors.navyMid,
        border: Border(
          top: BorderSide(color: AppColors.navyLight, width: 1),
        ),
      ),
      child: Row(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isActive = currentIndex == i;

          return Expanded(
            child: Semantics(
              label: item.label,
              selected: isActive,
              button: true,
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: AppSizes.minTouchTarget,
                  color: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: AppDurations.fast,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.saffron.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.icon,
                          size: 24,
                          color: isActive
                              ? AppColors.saffron
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w400,
                          color: isActive
                              ? AppColors.saffron
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
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
