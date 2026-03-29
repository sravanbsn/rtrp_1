import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';

// ── Mock guardian data ────────────────────────────────────────────────────────

class _Guardian {
  final String name;
  final String phone;
  final String relation;
  bool active;
  final String initials;

  _Guardian({
    required this.name,
    required this.phone,
    required this.relation,
    required this.initials,
    this.active = true,
  });
}

// ── SOS Setup Screen ──────────────────────────────────────────────────────────

class SosSetupScreen extends StatefulWidget {
  const SosSetupScreen({super.key});

  @override
  State<SosSetupScreen> createState() => _SosSetupScreenState();
}

class _SosSetupScreenState extends State<SosSetupScreen> {
  final List<_Guardian> _guardians = [
    _Guardian(
        name: 'Priya Sharma',
        phone: '+91 98765 43210',
        relation: 'Beti',
        initials: 'PS',
        active: true),
    _Guardian(
        name: 'Rahul Verma',
        phone: '+91 87654 32109',
        relation: 'Beta',
        initials: 'RV',
        active: false),
  ];

  // ── Auto-SOS settings ───────────────────────────────────────────
  bool _autoStopAlert = true;
  int _stopDelaySeconds = 45; // 30 / 45 / 60
  bool _fallDetection = true;
  bool _lowBattery = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        context.read<VoiceService>().speak(
              'Yeh aapki emergency settings hain. '
              'Aap guardian add ya remove kar sakte hain.',
            );
      }
    });
  }

  void _addGuardian() {
    context.read<VoiceService>().speak(
          'Naya guardian add karne ke liye naam boliye ya type karein.',
        );
    // TODO: open contact picker
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contact picker — coming soon'),
        backgroundColor: AppColors.navyCard,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Emergency Setup',
            style: TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ══ GUARDIAN CONTACTS ════════════════════════════════
            const _SectionHeader(
              icon: Icons.shield_rounded,
              label: 'Emergency Contacts',
              color: AppColors.saffron,
            ),
            const SizedBox(height: AppSizes.md),

            ..._guardians.asMap().entries.map((e) => _GuardianCard(
                  guardian: e.value,
                  index: e.key,
                  onToggle: (v) =>
                      setState(() => _guardians[e.key].active = v),
                  onRemove: () =>
                      setState(() => _guardians.removeAt(e.key)),
                )),

            // Add guardian button (max 3)
            if (_guardians.length < 3)
              Padding(
                padding: const EdgeInsets.only(top: AppSizes.sm, bottom: AppSizes.lg),
                child: Semantics(
                  label: 'Add new emergency contact',
                  button: true,
                  child: GestureDetector(
                    onTap: _addGuardian,
                    child: Container(
                      height: AppSizes.minTouchTarget,
                      decoration: BoxDecoration(
                        color: AppColors.navyCard,
                        borderRadius:
                            BorderRadius.circular(AppSizes.buttonRadius),
                        border: Border.all(
                            color: AppColors.saffron.withValues(alpha: 0.4),
                            style: BorderStyle.solid),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded,
                              color: AppColors.saffron),
                          SizedBox(width: AppSizes.sm),
                          Text('Guardian Add Karein',
                              style: TextStyle(
                                  color: AppColors.saffron,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ).animate(delay: 300.ms).fadeIn(duration: 300.ms),

            const Divider(color: AppColors.navyLight, height: 32),

            // ══ AUTO-SOS SETTINGS ════════════════════════════════
            const _SectionHeader(
              icon: Icons.auto_mode_rounded,
              label: 'Auto-SOS Settings',
              color: Color(0xFFFF6B6B),
            ),
            const SizedBox(height: AppSizes.md),

            // Ruk jaana alert
            _AutoSosTile(
              icon: Icons.timer_outlined,
              title: 'Ruk Jaana Alert',
              subtitle:
                  'Agar aap $_stopDelaySeconds second tak nahi hilte toh SOS bhejega',
              value: _autoStopAlert,
              onChanged: (v) => setState(() => _autoStopAlert = v),
              trailing: _autoStopAlert
                  ? _DelaySelector(
                      value: _stopDelaySeconds,
                      options: const [30, 45, 60],
                      onChanged: (v) =>
                          setState(() => _stopDelaySeconds = v),
                    )
                  : null,
            ).animate(delay: 400.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.sm),

            // Fall detection
            _AutoSosTile(
              icon: Icons.man_rounded,
              title: 'Girne Pe Alert',
              subtitle: 'Girne pe turant guardian ko SOS bhejega',
              value: _fallDetection,
              onChanged: (v) => setState(() => _fallDetection = v),
            ).animate(delay: 480.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.sm),

            // Low battery
            _AutoSosTile(
              icon: Icons.battery_alert_rounded,
              title: 'Battery Kam Ho',
              subtitle: 'Battery 10% se kam hone pe guardian ko notify karega',
              value: _lowBattery,
              onChanged: (v) => setState(() => _lowBattery = v),
            ).animate(delay: 560.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.xxl),

            // Save button
            Semantics(
              label: 'Save emergency settings',
              button: true,
              child: ElevatedButton.icon(
                onPressed: () {
                  context.read<VoiceService>().speak(
                        'Emergency settings save ho gayi. Aap safe hain.',
                      );
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  minimumSize:
                      const Size(double.infinity, AppSizes.minTouchTarget),
                ),
                icon: const Icon(Icons.save_rounded,
                    color: AppColors.navyDeep, size: 20),
                label: const Text('Settings Save Karein'),
              ),
            ).animate(delay: 640.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.xl),
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionHeader(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppSizes.sm),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ── Guardian card ─────────────────────────────────────────────────────────────

class _GuardianCard extends StatelessWidget {
  final _Guardian guardian;
  final int index;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  const _GuardianCard({
    required this.guardian,
    required this.index,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${guardian.name}, ${guardian.relation}. ${guardian.active ? "Active" : "Inactive"}.',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSizes.sm),
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: AppColors.navyCard,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(
            color: guardian.active
                ? AppColors.safeGreen.withValues(alpha: 0.4)
                : AppColors.navyLight,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: guardian.active
                    ? AppColors.saffron.withValues(alpha: 0.15)
                    : AppColors.navyLight,
              ),
              child: Center(
                child: Text(
                  guardian.initials,
                  style: TextStyle(
                    color: guardian.active
                        ? AppColors.saffron
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),

            const SizedBox(width: AppSizes.md),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(guardian.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 2),
                  Text('${guardian.relation} • ${guardian.phone}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),

            // Active toggle
            Column(
              children: [
                Switch(
                  value: guardian.active,
                  onChanged: onToggle,
                  activeThumbColor: AppColors.saffron,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                // Remove
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.textMuted, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 100 + index * 100))
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.06, end: 0);
  }
}

// ── Auto-SOS tile ─────────────────────────────────────────────────────────────

class _AutoSosTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;

  const _AutoSosTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(
            color: value
                ? AppColors.saffron.withValues(alpha: 0.3)
                : AppColors.navyLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon,
                  color: value ? AppColors.saffron : AppColors.textMuted,
                  size: 22),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: value
                                  ? AppColors.white
                                  : AppColors.textSecondary,
                            )),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted)),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: AppColors.saffron,
              ),
            ],
          ),
          if (trailing != null) ...[
            const SizedBox(height: AppSizes.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ── Delay selector ────────────────────────────────────────────────────────────

class _DelaySelector extends StatelessWidget {
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const _DelaySelector({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Delay:',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(width: AppSizes.sm),
        ...options.map((opt) {
          final isSelected = opt == value;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () => onChanged(opt),
              child: AnimatedContainer(
                duration: AppDurations.fast,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.saffron
                      : AppColors.navyLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${opt}s',
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.navyDeep
                        : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
