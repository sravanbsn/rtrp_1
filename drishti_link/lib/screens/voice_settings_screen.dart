import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/voice_service.dart';

class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  // ── Voice settings state ─────────────────────────────────────────
  double _speed = 0.5; // 0=Dheema, 0.5=Normal, 1=Tej
  double _volume = 0.8;
  String _language = 'Hindi';
  final String _wakeWord = 'Drishti';
  bool _screenOffListening = true;
  String _sensitivity = 'Medium';
  String _alertStyle = 'Moderate';
  final String _customEmergencyWord = 'Bachao';
  bool _recordingEmergency = false;

  // ── Silence zones ────────────────────────────────────────────────
  final List<String> _silenceZones = ['City Hospital', 'Shiv Mandir'];

  String get _speedLabel {
    if (_speed < 0.33) return 'Dheema';
    if (_speed < 0.66) return 'Normal';
    return 'Tej';
  }

  Future<void> _preview(String text) async {
    await context.read<VoiceService>().speak(text);
  }

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
        title: const Text('Drishti ki Awaaz',
            style:
                TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          Semantics(
            label: 'Preview voice settings',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.volume_up_rounded, color: AppColors.saffron),
              onPressed: () => _preview('Yeh Drishti ki awaaz settings hai.'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ══ SPEED + VOLUME + LANGUAGE ═══════════════════════
            const _SectionHeader('🔊 Awaaz Settings'),

            // Speed
            _SliderSection(
              icon: Icons.speed_rounded,
              title: 'Speed — $_speedLabel',
              value: _speed,
              label: _speedLabel,
              leftLabel: 'Dheema',
              rightLabel: 'Tej',
              onChanged: (v) => setState(() => _speed = v),
              onPreview: () =>
                  _preview('Yeh ek sample line hai Drishti ki awaaz mein.'),
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: AppSizes.sm),

            // Volume
            _SliderSection(
              icon: Icons.volume_up_rounded,
              title: 'Volume — ${(_volume * 100).round()}%',
              value: _volume,
              leftLabel: 'Halka',
              rightLabel: 'Tej',
              onChanged: (v) => setState(() => _volume = v),
              onPreview: () => _preview('Volume bilkul theek hai.'),
            ).animate(delay: 80.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: AppSizes.sm),

            // Language
            _PickerSection(
              icon: Icons.language_rounded,
              title: 'Language',
              value: _language,
              options: const [
                'Hindi',
                'English',
                'Telugu',
                'Tamil',
                'Hinglish'
              ],
              onChanged: (v) {
                setState(() => _language = v);
                final samples = {
                  'Hindi': 'Namaste! Main Drishti hoon.',
                  'English': 'Hello! I am Drishti.',
                  'Telugu': 'Namaskaram! Nenu Drishti ni.',
                  'Tamil': 'Vanakam! Naan Drishti.',
                  'Hinglish': 'Hi! Main Drishti hoon, ready to help!',
                };
                _preview(samples[v] ?? 'Hello!');
              },
            ).animate(delay: 160.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: AppSizes.lg),

            // ══ WAKE WORD ════════════════════════════════════════
            const _SectionHeader('🎙 Wake Word'),

            _InfoCard(
              icon: Icons.lock_rounded,
              title: '"$_wakeWord" — Always ON',
              subtitle: 'Navigation ke dauran disable nahi ho sakta.',
              color: AppColors.safeGreen,
            ).animate(delay: 200.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.sm),

            _SettingsRow(
              icon: Icons.fiber_manual_record_rounded,
              title: 'Custom Wake Word',
              subtitle: 'Apni awaaz mein record karein',
              trailing: _RecordButton(
                onRecord: () => _preview('Custom wake word record ho gaya.'),
              ),
            ),

            _SwitchRow(
              icon: Icons.screen_lock_portrait_rounded,
              title: 'Screen-off Listening',
              subtitle: 'Navigation pe hamesha ON rahega 🔒',
              value: _screenOffListening,
              lockWhenNav: true,
              onChanged: (v) => setState(() => _screenOffListening = v),
            ),

            _PickerSection(
              icon: Icons.tune_rounded,
              title: 'Sensitivity',
              value: _sensitivity,
              options: const ['Low', 'Medium', 'High'],
              onChanged: (v) {
                setState(() => _sensitivity = v);
                _preview('Sensitivity: $v.');
              },
            ).animate(delay: 240.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.lg),

            // ══ ALERT VOICE STYLE ════════════════════════════════
            const _SectionHeader('⚠ Alert Voice Style'),

            Row(
              children:
                  ['Gentle', 'Moderate', 'Urgent'].asMap().entries.map((e) {
                final i = e.key;
                final opt = e.value;
                final isSel = _alertStyle == opt;
                final colors = [
                  AppColors.safeGreen,
                  const Color(0xFFFFD600),
                  AppColors.hazardRed
                ];
                final icons = [
                  Icons.spa_rounded,
                  Icons.warning_amber_rounded,
                  Icons.priority_high_rounded
                ];

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                    child: Semantics(
                      selected: isSel,
                      button: true,
                      label: opt,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _alertStyle = opt);
                          _preview('Alert style: $opt.');
                        },
                        child: AnimatedContainer(
                          duration: AppDurations.fast,
                          padding:
                              const EdgeInsets.symmetric(vertical: AppSizes.md),
                          decoration: BoxDecoration(
                            color: isSel
                                ? colors[i].withValues(alpha: 0.15)
                                : AppColors.navyCard,
                            borderRadius:
                                BorderRadius.circular(AppSizes.buttonRadius),
                            border: Border.all(
                              color: isSel ? colors[i] : AppColors.navyLight,
                              width: isSel ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(icons[i], color: colors[i], size: 28),
                              const SizedBox(height: 6),
                              Text(opt,
                                  style: TextStyle(
                                      color: isSel
                                          ? colors[i]
                                          : AppColors.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ).animate(delay: 280.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.lg),

            // ══ SILENCE ZONES ════════════════════════════════════
            const _SectionHeader('🤫 Silence Zones'),
            const SizedBox(height: AppSizes.sm),

            ..._silenceZones.asMap().entries.map((e) => _SilenceZoneTile(
                  name: e.value,
                  onRemove: () => setState(() => _silenceZones.removeAt(e.key)),
                )),

            GestureDetector(
              onTap: () {
                setState(() => _silenceZones.add('New Place'));
                _preview('Silence zone add ho gaya.');
              },
              child: Container(
                height: 44,
                margin: const EdgeInsets.only(top: AppSizes.sm),
                decoration: BoxDecoration(
                  color: AppColors.navyCard,
                  borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
                  border: Border.all(
                      color: AppColors.saffron.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_location_rounded,
                        color: AppColors.saffron, size: 18),
                    SizedBox(width: 8),
                    Text('Jagah Add Karein',
                        style: TextStyle(
                            color: AppColors.saffron,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              ),
            ).animate(delay: 320.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.lg),

            // ══ EMERGENCY PHRASE ═════════════════════════════════
            const _SectionHeader('🆘 Emergency Phrase'),
            const SizedBox(height: AppSizes.sm),

            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.navyCard,
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                border: Border.all(
                    color: AppColors.hazardRed.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.record_voice_over_rounded,
                          color: AppColors.hazardRed, size: 20),
                      const SizedBox(width: AppSizes.sm),
                      Text('Current: "$_customEmergencyWord"',
                          style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      const Spacer(),
                      const Icon(Icons.volume_up_rounded,
                          color: AppColors.saffron, size: 18),
                    ],
                  ),
                  const SizedBox(height: AppSizes.sm),
                  const Text(
                    'Default: "Help" ya "Bachao". Apna custom word record karein.',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 44,
                          decoration: BoxDecoration(
                            color: _recordingEmergency
                                ? AppColors.hazardRed
                                : AppColors.hazardRed.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(AppSizes.buttonRadius),
                            border: Border.all(color: AppColors.hazardRed),
                          ),
                          child: Semantics(
                            label: 'Record emergency voice command',
                            button: true,
                            child: GestureDetector(
                              onTapDown: (_) =>
                                  setState(() => _recordingEmergency = true),
                              onTapUp: (_) async {
                                setState(() => _recordingEmergency = false);
                                await _preview(
                                  'Main samajh gayi. Jab bhi "$_customEmergencyWord" bolenge, main turant Priya ko bulaungi.',
                                );
                              },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _recordingEmergency
                                      ? Icons.fiber_manual_record_rounded
                                      : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _recordingEmergency
                                      ? 'Recording...'
                                      : 'Record',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                            .animate(target: _recordingEmergency ? 1 : 0)
                            .scaleXY(end: 1.04, duration: 200.ms),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate(delay: 360.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.xl),

            // Save
            ElevatedButton.icon(
              onPressed: () {
                _preview('Awaaz settings save ho gayi. Shukriya!');
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  minimumSize:
                      const Size(double.infinity, AppSizes.minTouchTarget)),
              icon: const Icon(Icons.save_rounded,
                  color: AppColors.navyDeep, size: 20),
              label: const Text('Settings Save Karein'),
            ).animate(delay: 400.ms).fadeIn(duration: 350.ms),

            const SizedBox(height: AppSizes.xl),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.saffron,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              fontSize: 12)),
    );
  }
}

class _SliderSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final String? label;
  final String leftLabel;
  final String rightLabel;
  final ValueChanged<double> onChanged;
  final VoidCallback onPreview;

  const _SliderSection({
    required this.icon,
    required this.title,
    required this.value,
    this.label,
    required this.leftLabel,
    required this.rightLabel,
    required this.onChanged,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.sm, AppSizes.sm, 0),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.saffron, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600))),
              Semantics(
                label: 'Preview $title voice',
                button: true,
                child: GestureDetector(
                  onTap: onPreview,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.volume_up_rounded,
                        color: AppColors.saffron, size: 18),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(leftLabel,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 10)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 8),
                    activeTrackColor: AppColors.saffron,
                    inactiveTrackColor: AppColors.navyLight,
                    thumbColor: AppColors.saffron,
                  ),
                  child: Slider(
                      value: value, onChanged: onChanged, min: 0, max: 1),
                ),
              ),
              Text(rightLabel,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _PickerSection({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.saffron, size: 18),
          const SizedBox(width: AppSizes.sm),
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600))),
          DropdownButton<String>(
            value: value,
            items: options
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            dropdownColor: AppColors.navyCard,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            iconEnabledColor: AppColors.saffron,
            underline: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _InfoCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSizes.sm),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 14)),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
            ],
          )),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;

  const _SettingsRow(
      {required this.icon,
      required this.title,
      this.subtitle,
      required this.trailing});

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
          Icon(icon, color: AppColors.saffron, size: 18),
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
          )),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final bool lockWhenNav;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.lockWhenNav = false,
    required this.onChanged,
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
          Icon(icon, color: AppColors.saffron, size: 18),
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
          )),
          if (lockWhenNav)
            const Icon(Icons.lock_rounded,
                color: AppColors.safeGreen, size: 16),
          const SizedBox(width: 4),
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

class _RecordButton extends StatelessWidget {
  final VoidCallback onRecord;
  const _RecordButton({required this.onRecord});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRecord,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.hazardRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hazardRed.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_rounded, color: AppColors.hazardRed, size: 16),
            SizedBox(width: 4),
            Text('Record',
                style: TextStyle(
                    color: AppColors.hazardRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SilenceZoneTile extends StatelessWidget {
  final String name;
  final VoidCallback onRemove;
  const _SilenceZoneTile({required this.name, required this.onRemove});

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
          const Icon(Icons.location_on_rounded,
              color: AppColors.textMuted, size: 18),
          const SizedBox(width: AppSizes.sm),
          Expanded(
              child: Text(name,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary))),
          const Text('Haptic only',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(width: 8),
          Semantics(
            label: 'Remove $name from silence zones',
            button: true,
            child: GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close_rounded,
                  color: AppColors.textMuted, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
