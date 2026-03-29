import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _nightMode = 'Auto';
  bool _routeLearning = true;
  bool _crowdWarnings = true;
  String _alertStyle = 'Seedha';

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Profile',
            style:
                TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar + Name ────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.saffron.withValues(alpha: 0.2),
                          border:
                              Border.all(color: AppColors.saffron, width: 2.5),
                        ),
                        child: const Center(
                          child: Text('AS',
                              style: TextStyle(
                                  color: AppColors.saffron,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.saffron,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.navyDeep, width: 2),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            color: AppColors.navyDeep, size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),
                  Text('Arjun Sharma',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('+91 98765 XXXXX',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  const SizedBox(height: AppSizes.md),
                  OutlinedButton.icon(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.saffron, width: 1.5),
                      foregroundColor: AppColors.saffron,
                      minimumSize: const Size(160, 40),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Profile',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 500.ms),

            const SizedBox(height: AppSizes.xl),

            // ── Voice & Alerts ───────────────────────────────────
            const _SectionLabel('🔊 Awaaz aur Alerts'),
            const SizedBox(height: AppSizes.sm),
            _NavTile(
                icon: Icons.language_rounded,
                title: 'Language',
                value: 'Hindi',
                onPreview: () =>
                    context.read<VoiceService>().speak('Yeh Hindi awaaz hai.'),
                onTap: () {}),
            _SegTile(
                icon: Icons.notifications_active_rounded,
                title: 'Alert Style',
                value: _alertStyle,
                options: const ['Halka', 'Seedha', 'Urgent'],
                onChanged: (v) => setState(() => _alertStyle = v),
                onPreview: () => context
                    .read<VoiceService>()
                    .speak('Alert style: $_alertStyle.')),
            _NavTile(
                icon: Icons.settings_voice_rounded,
                title: 'Voice Settings',
                onPreview: () =>
                    context.read<VoiceService>().speak('Voice settings.'),
                onTap: () => Navigator.pushNamed(context, '/voice-settings')),

            const SizedBox(height: AppSizes.md),

            // ── Guardian ─────────────────────────────────────────
            const _SectionLabel('🛡 Guardian'),
            const SizedBox(height: AppSizes.sm),
            _NavTile(
                icon: Icons.person_rounded,
                title: 'Priya Sharma',
                subtitle: '+91 98765 43210',
                trailing: _OnlinePill(),
                onPreview: () => context
                    .read<VoiceService>()
                    .speak('Priya Sharma. Online hai.'),
                onTap: () {}),
            _NavTile(
                icon: Icons.person_add_rounded,
                title: 'Guardian Add Karo',
                onPreview: () => context
                    .read<VoiceService>()
                    .speak('Naya guardian add karein.'),
                onTap: () {}),
            _NavTile(
                icon: Icons.sos_rounded,
                title: 'SOS Settings',
                onPreview: () =>
                    context.read<VoiceService>().speak('SOS settings.'),
                onTap: () => Navigator.pushNamed(context, '/sos/setup')),

            const SizedBox(height: AppSizes.md),

            // ── Navigation ───────────────────────────────────────
            const _SectionLabel('🗺 Navigation'),
            const SizedBox(height: AppSizes.sm),
            _SegTile(
                icon: Icons.nightlight_round,
                title: 'Night Mode',
                value: _nightMode,
                options: const ['Auto', 'On', 'Off'],
                onChanged: (v) => setState(() => _nightMode = v),
                onPreview: () => context
                    .read<VoiceService>()
                    .speak('Night mode: $_nightMode.')),
            _SwitchTile(
                icon: Icons.route_rounded,
                title: 'Route Learning',
                subtitle: 'Drishti aapke routes yaad rakhti hai',
                value: _routeLearning,
                onChanged: (v) => setState(() => _routeLearning = v),
                onPreview: () => context
                    .read<VoiceService>()
                    .speak('Route learning ${_routeLearning ? "on" : "off"}.')),
            _SwitchTile(
                icon: Icons.groups_rounded,
                title: 'Crowd Warnings',
                subtitle: 'Bheed wali jagah pe alert dega',
                value: _crowdWarnings,
                onChanged: (v) => setState(() => _crowdWarnings = v),
                onPreview: () => context
                    .read<VoiceService>()
                    .speak('Crowd warnings ${_crowdWarnings ? "on" : "off"}.')),

            const SizedBox(height: AppSizes.md),

            // ── Account ──────────────────────────────────────────
            const _SectionLabel('👤 Account'),
            const SizedBox(height: AppSizes.sm),
            _NavTile(
                icon: Icons.privacy_tip_rounded,
                title: 'Privacy Policy',
                onTap: () {}),
            _NavTile(
                icon: Icons.help_outline_rounded,
                title: 'Help & Support',
                onPreview: () => context
                    .read<VoiceService>()
                    .speak('Help screen aane wala hai.'),
                onTap: () {}),

            const SizedBox(height: AppSizes.sm),

            Semantics(
              label: 'Sign out',
              button: true,
              child: GestureDetector(
                onTap: () {
                  context
                      .read<VoiceService>()
                      .speak('Sign out kar rahe hain. Alvida!');
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/login/phone', (_) => false);
                },
                child: Container(
                  width: double.infinity,
                  height: AppSizes.minTouchTarget,
                  decoration: BoxDecoration(
                    color: AppColors.navyCard,
                    borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
                    border: Border.all(color: AppColors.navyLight),
                  ),
                  child: const Center(
                    child: Text('Sign Out',
                        style: TextStyle(
                            color: AppColors.hazardRed,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                  ),
                ),
              ),
            ).animate(delay: 400.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: AppSizes.xxl),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: AppColors.saffron,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 12));
  }
}

class _OnlinePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.safeGreen.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.safeGreen.withValues(alpha: 0.5)),
      ),
      child: const Text('🟢 Online',
          style: TextStyle(
              color: AppColors.safeGreen,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onPreview;

  const _NavTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: title,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding:
              const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.navyCard,
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.saffron, size: 20),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (value != null)
                Text(value!,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 13)),
              if (onPreview != null)
                GestureDetector(
                  onTap: onPreview,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.volume_up_rounded,
                        color: AppColors.saffron, size: 18),
                  ),
                ),
              trailing ??
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final VoidCallback? onPreview;

  const _SegTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding:
          const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.saffron, size: 20),
          const SizedBox(width: AppSizes.md),
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600))),
          if (onPreview != null)
            GestureDetector(
              onTap: onPreview,
              child: const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.volume_up_rounded,
                    color: AppColors.saffron, size: 18),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final isSel = opt == value;
              return GestureDetector(
                onTap: () => onChanged(opt),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: isSel ? AppColors.saffron : AppColors.navyLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(opt,
                      style: TextStyle(
                        color: isSel ? AppColors.navyDeep : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      )),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onPreview;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding:
          const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.saffron, size: 20),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          if (onPreview != null)
            GestureDetector(
              onTap: onPreview,
              child: const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.volume_up_rounded,
                    color: AppColors.saffron, size: 18),
              ),
            ),
          Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.saffron,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ],
      ),
    );
  }
}
