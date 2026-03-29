
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/theme.dart';
import '../services/voice_service.dart';

// ── Data model ───────────────────────────────────────────────────────────────

enum AlertLevel { danger, warning, safe }

class AlertRecord {
  final AlertLevel level;
  final String time;
  final String title;
  final String location;
  final String detail;
  final DateTime timestamp;

  const AlertRecord({
    required this.level,
    required this.time,
    required this.title,
    required this.location,
    required this.detail,
    required this.timestamp,
  });

  String get voiceLine => '$time pe, $title. Location: $location. $detail';
}

// ── Mock data ────────────────────────────────────────────────────────────────

final _allAlerts = <AlertRecord>[
  AlertRecord(
    level: AlertLevel.danger,
    time: '2:34 PM',
    title: 'Gaadi aa rahi thi — main ne rokaa',
    location: 'Gandhi Nagar Junction ke paas',
    detail:
        'Do baje chalees minute pe, ek gaadi 8 meter pe thi. Main ne aapko rokaa. Aap safe the.',
    timestamp: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  AlertRecord(
    level: AlertLevel.warning,
    time: '11:12 AM',
    title: 'Pothole mila — reroute kiya',
    location: 'Station Road footpath',
    detail:
        'Gyarah baje baara minute pe, ek gaddha tha left side mein. Main ne aapko right le gayi.',
    timestamp: DateTime.now().subtract(const Duration(hours: 4)),
  ),
  AlertRecord(
    level: AlertLevel.safe,
    time: '9:05 AM',
    title: 'Rasta saaf tha — chale gaye',
    location: 'Ghar se nikal ke',
    detail:
        'Naun baje paanch minute pe, rasta bilkul saaf tha. Koi hazard detect nahi hua.',
    timestamp: DateTime.now().subtract(const Duration(hours: 6)),
  ),
  AlertRecord(
    level: AlertLevel.warning,
    time: 'Kal 6:22 PM',
    title: 'Cycle wala tez aaya',
    location: 'Market ke bahar',
    detail:
        'Kal shaam chhe baje baais minute pe, ek sawaari tez aa rahi thi. Alert diya gaya.',
    timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 1)),
  ),
  AlertRecord(
    level: AlertLevel.danger,
    time: 'Kal 3:47 PM',
    title: 'Intersection pe gaadi — immediate stop',
    location: 'Subhash Chowk',
    detail:
        'Kal teen baje saintees minute pe, ek gaadi tez nikal rahi thi. Aapko rokaa. Aap safe the.',
    timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
  ),
];

// ── Filter ───────────────────────────────────────────────────────────────────

enum _Filter { today, week, all }

List<AlertRecord> _filterAlerts(_Filter f) {
  final now = DateTime.now();
  switch (f) {
    case _Filter.today:
      return _allAlerts.where((a) {
        return now.difference(a.timestamp).inHours < 24 &&
            a.timestamp.day == now.day;
      }).toList();
    case _Filter.week:
      return _allAlerts
          .where((a) => now.difference(a.timestamp).inDays < 7)
          .toList();
    case _Filter.all:
      return _allAlerts;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERTS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  _Filter _filter = _Filter.today;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initAndGreet();
  }

  Future<void> _initAndGreet() async {
    _speechAvailable = await _speech.initialize();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final count = _filterAlerts(_Filter.today).length;
    final greeting = count == 0
        ? 'Aaj koi alert nahi aaya. Bahut acha!'
        : 'Aaj $count alert ${count == 1 ? "aaya" : "aaye"}. Sunna chahenge?';

    await context.read<VoiceService>().speak(greeting);
    if (!mounted) return;

    if (count > 0) _listenForYesNo();
  }

  void _listenForYesNo() {
    if (!_speechAvailable || !mounted) return;
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 4),
      onResult: (r) {
        if (!r.finalResult) return;
        final w = r.recognizedWords.toLowerCase();
        if (w.contains('haan') || w.contains('ha') || w.contains('yes')) {
          _readAllAloud();
        }
      },
    );
  }

  Future<void> _readAllAloud() async {
    final alerts = _filterAlerts(_filter);
    for (final a in alerts) {
      if (!mounted) return;
      await context.read<VoiceService>().speak(a.voiceLine);
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  Future<void> _readSingle(AlertRecord alert) async {
    await context.read<VoiceService>().speak(alert.detail);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _filterAlerts(_filter);

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
        title: const Text('Alert History',
            style:
                TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          // Read all button
          Semantics(
            label: 'Read all alerts aloud',
            button: true,
            child: IconButton(
              icon:
                  const Icon(Icons.volume_up_rounded, color: AppColors.saffron),
              onPressed: _readAllAloud,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter tabs ─────────────────────────────────────────
          _FilterTabs(
            selected: _filter,
            onSelect: (f) => setState(() => _filter = f),
          ),

          const SizedBox(height: AppSizes.sm),

          // ── List or empty ───────────────────────────────────────
          Expanded(
            child: alerts.isEmpty
                ? _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSizes.lg, AppSizes.sm, AppSizes.lg, AppSizes.xl),
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSizes.sm),
                    itemBuilder: (_, i) => _AlertCard(
                      alert: alerts[i],
                      index: i,
                      onRead: () => _readSingle(alerts[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Filter tabs ──────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  final _Filter selected;
  final ValueChanged<_Filter> onSelect;

  const _FilterTabs({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const items = [
      (_Filter.today, 'Aaj'),
      (_Filter.week, 'Is Hafte'),
      (_Filter.all, 'Sab'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.navyCard,
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
        child: Row(
          children: items.map((item) {
            final isSelected = selected == item.$1;
            return Expanded(
              child: Semantics(
                label: item.$2,
                selected: isSelected,
                button: true,
                child: GestureDetector(
                  onTap: () => onSelect(item.$1),
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          isSelected ? AppColors.saffron : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(AppSizes.buttonRadius - 4),
                    ),
                    child: Center(
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.navyDeep
                              : AppColors.textMuted,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Alert card ───────────────────────────────────────────────────────────────

class _AlertCard extends StatefulWidget {
  final AlertRecord alert;
  final int index;
  final VoidCallback onRead;

  const _AlertCard(
      {required this.alert, required this.index, required this.onRead});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _expanded = false;

  Color get _borderColor {
    switch (widget.alert.level) {
      case AlertLevel.danger:
        return AppColors.hazardRed;
      case AlertLevel.warning:
        return const Color(0xFFFFD600);
      case AlertLevel.safe:
        return AppColors.safeGreen;
    }
  }

  String get _levelDot {
    switch (widget.alert.level) {
      case AlertLevel.danger:
        return '🔴';
      case AlertLevel.warning:
        return '🟡';
      case AlertLevel.safe:
        return '🟢';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${widget.alert.time} — ${widget.alert.title}. ${widget.alert.location}. Double tap to expand.',
      button: true,
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.navyCard,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border(
              left: BorderSide(color: _borderColor, width: 4),
              top: const BorderSide(color: AppColors.navyLight, width: 0.5),
              right: const BorderSide(color: AppColors.navyLight, width: 0.5),
              bottom: const BorderSide(color: AppColors.navyLight, width: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Main row ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(AppSizes.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_levelDot, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.alert.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.access_time_rounded,
                                  color: AppColors.textMuted, size: 13),
                              const SizedBox(width: 4),
                              Text(widget.alert.time,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textMuted)),
                              const SizedBox(width: AppSizes.sm),
                              const Icon(Icons.location_on_rounded,
                                  color: AppColors.textMuted, size: 13),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.alert.location,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Expand + speaker icons
                    Column(
                      children: [
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textMuted,
                        ),
                        Semantics(
                          label: 'Read alert aloud',
                          button: true,
                          child: IconButton(
                            icon: const Icon(Icons.volume_up_rounded,
                                color: AppColors.saffron, size: 18),
                            onPressed: widget.onRead,
                            tooltip: 'Read aloud',
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Expanded detail ───────────────────────────
              if (_expanded)
                Container(
                  padding: const EdgeInsets.fromLTRB(
                      AppSizes.lg, 0, AppSizes.md, AppSizes.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: AppColors.navyLight),
                      const SizedBox(height: AppSizes.sm),
                      // Drishti's explanation
                      Container(
                        padding: const EdgeInsets.all(AppSizes.md),
                        decoration: BoxDecoration(
                          color: _borderColor.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(AppSizes.buttonRadius),
                          border: Border.all(
                              color: _borderColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🎙', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: AppSizes.sm),
                            Expanded(
                              child: Text(
                                widget.alert.detail,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                      height: 1.5,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      // Mini "map" placeholder
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.navyLight,
                          borderRadius:
                              BorderRadius.circular(AppSizes.buttonRadius),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.map_rounded,
                                  color: AppColors.textMuted, size: 20),
                              SizedBox(width: 8),
                              Text('Map view — coming soon',
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 250.ms)
                    .slideY(begin: -0.05, end: 0),
            ],
          ),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: widget.index * 80))
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.06, end: 0);
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 64)),
          const SizedBox(height: AppSizes.lg),
          Text(
            'Aaj koi alert nahi aaya.',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Bahut achha!',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.safeGreen,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ).animate().fadeIn(duration: 500.ms).scaleXY(begin: 0.9, end: 1.0),
    );
  }
}
