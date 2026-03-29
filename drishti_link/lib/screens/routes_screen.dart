import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class SavedRoute {
  final String name;
  final String from;
  final String to;
  final double distanceKm;
  final int durationMin;
  final double safetyScore;
  final String lastUsed;
  final int knownHazards;
  bool isFavorite;

  SavedRoute({
    required this.name,
    required this.from,
    required this.to,
    required this.distanceKm,
    required this.durationMin,
    required this.safetyScore,
    required this.lastUsed,
    required this.knownHazards,
    this.isFavorite = false,
  });

  String get voiceLine =>
      '$name. ${distanceKm}km, $durationMin minute. Safety score: $safetyScore. '
      'Last used: $lastUsed. Hazards: $knownHazards.';
}

// ── Mock data ──────────────────────────────────────────────────────────────────

final _allRoutes = [
  SavedRoute(
    name: 'Ghar → Market',
    from: 'Ghar',
    to: 'Market',
    distanceKm: 1.2,
    durationMin: 8,
    safetyScore: 4.8,
    lastUsed: 'Kal',
    knownHazards: 2,
    isFavorite: true,
  ),
  SavedRoute(
    name: 'Ghar → Bus Stand',
    from: 'Ghar',
    to: 'Bus Stand',
    distanceKm: 0.7,
    durationMin: 5,
    safetyScore: 4.5,
    lastUsed: '3 din pehle',
    knownHazards: 1,
    isFavorite: true,
  ),
  SavedRoute(
    name: 'Market → Hospital',
    from: 'Market',
    to: 'City Hospital',
    distanceKm: 2.1,
    durationMin: 15,
    safetyScore: 4.2,
    lastUsed: 'Is hafte',
    knownHazards: 4,
  ),
  SavedRoute(
    name: 'Ghar → Park',
    from: 'Ghar',
    to: 'Gandhi Park',
    distanceKm: 0.5,
    durationMin: 4,
    safetyScore: 4.9,
    lastUsed: 'Aaj',
    knownHazards: 0,
  ),
];

enum _RouteFilter { all, favorites, recent }

// ─────────────────────────────────────────────────────────────────────────────
// ROUTES SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  _RouteFilter _filter = _RouteFilter.all;

  List<SavedRoute> get _filtered {
    switch (_filter) {
      case _RouteFilter.all:
        return _allRoutes;
      case _RouteFilter.favorites:
        return _allRoutes.where((r) => r.isFavorite).toList();
      case _RouteFilter.recent:
        // recent = used today or yesterday
        return _allRoutes
            .where((r) => r.lastUsed == 'Aaj' || r.lastUsed == 'Kal')
            .toList();
    }
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        context.read<VoiceService>().speak(
              'Aapke safe routes. Kaun sa route chahiye?',
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final routes = _filtered;

    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Semantics(
          label: 'Go back to previous screen',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text('Safe Routes',
            style: TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          Semantics(
            label: 'Search routes',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.search_rounded, color: AppColors.saffron),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ══ MAP PLACEHOLDER (top 35%) ══════════════════════════
          _MapPlaceholder(routes: routes),

          // ══ FILTER CHIPS ═══════════════════════════════════════
          _FilterChips(
            selected: _filter,
            onSelect: (f) => setState(() => _filter = f),
          ),

          // ══ ROUTE LIST ═════════════════════════════════════════
          Expanded(
            child: routes.isEmpty
                ? _EmptyRoutes()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSizes.lg,
                        AppSizes.sm,
                        AppSizes.lg,
                        AppSizes.xxl + 16),
                    itemCount: routes.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSizes.sm),
                    itemBuilder: (_, i) => _RouteCard(
                      route: routes[i],
                      index: i,
                      onFavoriteToggle: () =>
                          setState(() => routes[i].isFavorite = !routes[i].isFavorite),
                      onNavigate: () {
                        context.read<VoiceService>().speak(
                              '${routes[i].name} route shuru kar rahi hoon.',
                            );
                        Navigator.pushNamed(context, '/navigation');
                      },
                      onRead: () {
                        context.read<VoiceService>().speak(routes[i].voiceLine);
                      },
                    ),
                  ),
          ),
        ],
      ),

      // ══ FAB — Record new route ════════════════════════════════
      floatingActionButton: Semantics(
        label: 'Record a new route',
        button: true,
        child: FloatingActionButton.extended(
          onPressed: () {
            HapticFeedback.heavyImpact();
            context.read<VoiceService>().speak(
                  'Naya route record karna shuru karein. Chalna shuru karein.',
                );
          },
          backgroundColor: AppColors.saffron,
          foregroundColor: AppColors.navyDeep,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Naya Route',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

// ── Mini map placeholder ───────────────────────────────────────────────────────

class _MapPlaceholder extends StatelessWidget {
  final List<SavedRoute> routes;
  const _MapPlaceholder({required this.routes});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.22;
    return Container(
      height: h,
      margin: const EdgeInsets.fromLTRB(
          AppSizes.lg, 0, AppSizes.lg, AppSizes.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.navyLight),
      ),
      child: CustomPaint(
        painter: _MapPainter(routeCount: routes.length),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_rounded,
                  color: AppColors.saffron, size: 32),
              const SizedBox(height: 6),
              Text(
                '${routes.length} saved routes',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const Text(
                'Map integration coming soon',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final int routeCount;
  const _MapPainter({required this.routeCount});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.saffron.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Draw simulated route lines
    final paths = [
      [Offset(size.width * 0.1, size.height * 0.8),
       Offset(size.width * 0.4, size.height * 0.5),
       Offset(size.width * 0.7, size.height * 0.4),
       Offset(size.width * 0.9, size.height * 0.2)],
      [Offset(size.width * 0.15, size.height * 0.85),
       Offset(size.width * 0.3, size.height * 0.6),
       Offset(size.width * 0.6, size.height * 0.65),
       Offset(size.width * 0.85, size.height * 0.3)],
    ];

    for (int i = 0; i < (routeCount < 2 ? 1 : 2); i++) {
      final p = Path();
      final pts = paths[i];
      p.moveTo(pts[0].dx, pts[0].dy);
      for (int j = 1; j < pts.length; j++) {
        p.lineTo(pts[j].dx, pts[j].dy);
      }
      paint.color = i == 0
          ? AppColors.saffron.withValues(alpha: 0.5)
          : AppColors.safeGreen.withValues(alpha: 0.4);
      canvas.drawPath(p, paint);

      // Origin dot
      canvas.drawCircle(pts[0], 5,
          Paint()..color = AppColors.saffron.withValues(alpha: 0.7)..style = PaintingStyle.fill);
      // Dest dot
      canvas.drawCircle(pts.last, 5,
          Paint()..color = AppColors.safeGreen.withValues(alpha: 0.7)..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.routeCount != routeCount;
}

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final _RouteFilter selected;
  final ValueChanged<_RouteFilter> onSelect;

  const _FilterChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const items = [
      (_RouteFilter.all, 'Sab'),
      (_RouteFilter.favorites, '⭐ Favorites'),
      (_RouteFilter.recent, '🕐 Recent'),
    ];

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        children: items.map((item) {
          final isSelected = selected == item.$1;
          return Padding(
            padding: const EdgeInsets.only(right: AppSizes.sm),
            child: Semantics(
              selected: isSelected,
              button: true,
              label: item.$2,
              child: GestureDetector(
                onTap: () => onSelect(item.$1),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.saffron
                        : AppColors.navyCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.saffron
                          : AppColors.navyLight,
                    ),
                  ),
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.navyDeep
                          : AppColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 13,
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

// ── Route card ────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final SavedRoute route;
  final int index;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onNavigate;
  final VoidCallback onRead;

  const _RouteCard({
    required this.route,
    required this.index,
    required this.onFavoriteToggle,
    required this.onNavigate,
    required this.onRead,
  });

  Color get _hazardColor {
    if (route.knownHazards == 0) return AppColors.safeGreen;
    if (route.knownHazards <= 2) return const Color(0xFFFFD600);
    return AppColors.hazardRed;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${route.name}. ${route.distanceKm} km, ${route.durationMin} minutes. '
          'Safety: ${route.safetyScore}. Tap to hear more.',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.navyCard,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(color: AppColors.navyLight),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ────────────────────────────────
              Row(
                children: [
                  // Route icon
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.saffron.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.route_rounded,
                        color: AppColors.saffron, size: 22),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(route.name,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            _InfoChip('${route.distanceKm} km',
                                Icons.straighten_rounded),
                            const SizedBox(width: 6),
                            _InfoChip('${route.durationMin} min',
                                Icons.timer_outlined),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Favorite + read
                  Column(
                    children: [
                      GestureDetector(
                        onTap: onFavoriteToggle,
                        child: Icon(
                          route.isFavorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: route.isFavorite
                              ? AppColors.saffron
                              : AppColors.textMuted,
                          size: 24,
                        ),
                      ),
                      GestureDetector(
                        onTap: onRead,
                        child: const Icon(Icons.volume_up_rounded,
                            color: AppColors.saffron, size: 20),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: AppSizes.md),

              // ── Stats row ─────────────────────────────────
              Row(
                children: [
                  // Safety score
                  _StatBadge(
                    label: '⭐ ${route.safetyScore}',
                    color: AppColors.saffron,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  // Hazards
                  _StatBadge(
                    label:
                        '⚠ ${route.knownHazards} hazard${route.knownHazards == 1 ? "" : "s"}',
                    color: _hazardColor,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  // Last used
                  _StatBadge(
                    label: '🕐 ${ route.lastUsed}',
                    color: AppColors.textMuted,
                  ),
                ],
              ),

              const SizedBox(height: AppSizes.md),

              // ── Action buttons ────────────────────────────
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Semantics(
                      label: 'Navigate ${route.name}',
                      button: true,
                      child: ElevatedButton.icon(
                        onPressed: onNavigate,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: const Icon(Icons.navigation_rounded,
                            size: 16, color: AppColors.navyDeep),
                        label: const Text('Navigate',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.navyDeep)),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Semantics(
                      label: 'Route details for ${route.name}',
                      button: true,
                      child: OutlinedButton(
                        onPressed: () {
                          context.read<VoiceService>().speak(
                                '${route.name}. ${route.voiceLine}',
                              );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          side: const BorderSide(
                              color: AppColors.navyLight),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Details',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: index * 80))
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.06, end: 0);
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  final IconData icon;
  const _InfoChip(this.text, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textMuted),
        const SizedBox(width: 3),
        Text(text,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyRoutes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route_rounded,
              color: AppColors.navyLight, size: 64),
          const SizedBox(height: AppSizes.md),
          Text('Koi route nahi mila',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: AppSizes.sm),
          const Text('+ se naya route record karein',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
